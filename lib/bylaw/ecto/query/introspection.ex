defmodule Bylaw.Ecto.Query.Introspection do
  @moduledoc """
  Read helpers for Ecto query structures used by query checks.

  Bylaw checks run from `c:Ecto.Repo.prepare_query/3`, after the caller has
  built an `Ecto.Query` through the Ecto query API and before the adapter sends
  SQL to the database. This module collects the small pieces of query structure
  that checks commonly need: root schemas, explicit join schemas, aliases,
  combination branches, nested queries, binding references, field references,
  and schema field metadata.

  The helpers intentionally inspect the query and expression data produced by
  Ecto. That inspectability is what lets Bylaw enforce application-specific
  query rules before runtime SQL execution. The supported shapes are covered by
  these helper tests and by the checks that use them; when Ecto changes those
  shapes, this module is the narrow place to update.

  Unknown, schema-less, association-derived, or unsupported shapes return
  `:unknown`, `:skip`, `%{}`, `MapSet.new()`, or `false` depending on the
  helper. Query checks should treat those values as "not statically proven"
  rather than trying to guess.
  """

  @typedoc """
  A path from the root query into nested Ecto combination queries.
  """
  @type branch_path :: list({atom(), non_neg_integer()})

  @typedoc """
  A query branch paired with its path from the root query.
  """
  @type query_branch :: {branch_path(), term()}

  @typedoc """
  A field name extracted from an Ecto field expression.
  """
  @type field_name :: atom() | String.t()

  @expression_subquery_fields [
    :distinct,
    :select,
    :wheres,
    :havings,
    :order_bys,
    :group_bys,
    :windows
  ]

  @doc """
  Returns the root schema module for an Ecto query.

  The root schema is read from the query's `from` source. `{:ok, schema}` is
  returned only when the source points at a module that exports `__schema__/1`.
  Schema-less sources, malformed values, and non-query values return
  `:unknown`.
  """
  @spec root_schema(term()) :: {:ok, module()} | :unknown
  def root_schema(%{from: %{source: {_source, schema}}})
      when is_atom(schema) and not is_nil(schema) do
    if function_exported?(schema, :__schema__, 1) do
      {:ok, schema}
    else
      :unknown
    end
  end

  def root_schema(_query), do: :unknown

  @doc """
  Returns the schema module for a direct explicit join.

  `{:ok, schema}` is returned for joins whose source points directly at an Ecto
  schema module. Association joins return `:skip`, because the association can
  already encode application-specific join behavior and most checks only need
  to reason about direct explicit joins. Schema-less joins, malformed joins, and
  non-schema sources also return `:skip`.
  """
  @spec explicit_join_schema(term()) :: {:ok, module()} | :skip
  def explicit_join_schema(%{assoc: assoc}) when assoc != nil, do: :skip

  def explicit_join_schema(%{source: {_source, schema}})
      when is_atom(schema) and not is_nil(schema) do
    if function_exported?(schema, :__schema__, 1) do
      {:ok, schema}
    else
      :skip
    end
  end

  def explicit_join_schema(_join), do: :skip

  @doc """
  Returns the named binding aliases for a query.

  The returned map uses alias names as keys and positional binding indexes as
  values. Values without an aliases map return an empty map.
  """
  @spec aliases(term()) :: map()
  def aliases(%{aliases: aliases}) when is_map(aliases), do: aliases
  def aliases(_query), do: %{}

  @doc """
  Returns the named aliases that point at the root binding.

  Root aliases are aliases whose binding index is `0`. Checks that only inspect
  the root schema can pass this set to `root_field/2` or `root_fields/2`.
  """
  @spec root_aliases(term()) :: MapSet.t(atom())
  def root_aliases(query) do
    query
    |> aliases()
    |> Enum.flat_map(fn
      {alias_name, 0} -> [alias_name]
      _alias -> []
    end)
    |> MapSet.new()
  end

  @doc """
  Returns the root query and every nested combination query branch.

  Ecto stores `union`, `union_all`, `except`, `except_all`, `intersect`, and
  `intersect_all` branches under the query's combinations. Checks that must
  validate every branch independently can use this helper to traverse those
  combinations consistently.

  Each returned tuple contains `{branch_path, query}`. The root query has an
  empty branch path. Combination branch paths contain `{operation, index}`
  entries, where `operation` is the combination operation and `index` is the
  zero-based position within that query's combinations.
  """
  @spec query_branches(term()) :: list(query_branch())
  def query_branches(query) do
    query
    |> query_branches([])
    |> Enum.map(fn {branch_path, branch_query} -> {Enum.reverse(branch_path), branch_query} end)
  end

  @doc """
  Returns the direct nested queries referenced by an Ecto query.

  This covers source and join subqueries, CTE query bodies, combination
  branches, and expression subqueries stored by Ecto query expressions such as
  `select`, `where`, `having`, `order_by`, `group_by`, `distinct`, and
  `windows`.

  The returned list contains only the immediate nested query references for the
  given query. Checks that need full-depth validation should recursively call
  this helper for returned queries.
  """
  @spec nested_queries(term()) :: list(term())
  def nested_queries(query) when is_map(query) do
    source_queries(query) ++
      join_queries(query) ++
      cte_queries(query) ++ combination_queries(query) ++ expression_queries(query)
  end

  def nested_queries(_query), do: []

  @doc """
  Formats a combination branch path for issue metadata.

  The root branch returns an empty map. Combination branches return a
  `:combination_path` list with `%{operation: operation, index: index}` entries.
  """
  @spec combination_path_meta(branch_path()) :: map()
  def combination_path_meta([]), do: %{}

  def combination_path_meta(branch_path) do
    %{combination_path: Enum.map(branch_path, &combination_path_entry/1)}
  end

  @doc """
  Resolves an Ecto binding expression to a positional binding index.

  Supports positional binding expressions such as `&0` and named binding
  expressions produced by `as(:name)`. Missing, malformed, or unresolved
  bindings return `:unknown`.
  """
  @spec binding_index(term(), map()) :: {:ok, non_neg_integer()} | :unknown
  def binding_index({:&, _meta, [binding_index]}, _aliases)
      when is_integer(binding_index) and binding_index >= 0 do
    {:ok, binding_index}
  end

  def binding_index({:as, _meta, [name]}, aliases) when is_atom(name) do
    case Map.fetch(aliases, name) do
      {:ok, binding_index} when is_integer(binding_index) and binding_index >= 0 ->
        {:ok, binding_index}

      _other ->
        :unknown
    end
  end

  def binding_index(_source, _aliases), do: :unknown

  @doc """
  Resolves a field expression to its binding index and field name.

  Supports the dot-field expression shape produced by `post.status` and the
  dynamic field expression shape produced by `field(post, :status)`. The source
  binding is resolved with `binding_index/2`. Non-field expressions and
  unresolved bindings return `:unknown`.
  """
  @spec field(term(), map()) :: {:ok, {non_neg_integer(), atom()}} | :unknown
  def field({{:., _meta, [source, field]}, _call_meta, []}, aliases) when is_atom(field) do
    field(source, field, aliases)
  end

  def field({:field, _meta, [source, field]}, aliases) when is_atom(field) do
    field(source, field, aliases)
  end

  def field(_expr, _aliases), do: :unknown

  @doc """
  Resolves a field expression only when it targets the root binding.

  The second argument may be either a full aliases map or the root alias set
  returned by `root_aliases/1`. Positional root fields such as `&0.status` and
  named root fields such as `as(:post).status` return `{:ok, field}`. Fields on
  joins, non-field expressions, and unresolved bindings return `:unknown`.
  """
  @spec root_field(term(), map() | MapSet.t(atom())) :: {:ok, atom()} | :unknown
  def root_field({{:., _meta, [source, field]}, _call_meta, []}, aliases_or_root_aliases)
      when is_atom(field) do
    if root_binding?(source, aliases_or_root_aliases) do
      {:ok, field}
    else
      :unknown
    end
  end

  def root_field({:field, _meta, [source, field]}, aliases_or_root_aliases) when is_atom(field) do
    if root_binding?(source, aliases_or_root_aliases) do
      {:ok, field}
    else
      :unknown
    end
  end

  def root_field(_expr, _aliases_or_root_aliases), do: :unknown

  @doc """
  Returns the root field referenced by `expr`, or an empty list.

  This wrapper is convenient when a check is accumulating field lists from many
  expressions and wants unsupported expressions to contribute no fields.
  """
  @spec root_fields(term(), map() | MapSet.t(atom())) :: list(atom())
  def root_fields(expr, aliases_or_root_aliases) do
    case root_field(expr, aliases_or_root_aliases) do
      {:ok, field} -> [field]
      :unknown -> []
    end
  end

  @doc """
  Resolves a direct root field expression and unwraps `type/2` wrappers.

  This helper accepts dot-field expressions such as `&0.status`, dynamic field
  expressions such as `field(&0, :status)`, and the same expressions wrapped by
  Ecto's `type/2`. Unlike `root_field/2`, it returns binary field names too, so
  callers that compare against atom field configuration can decide how to
  normalize those names.
  """
  @spec direct_root_field(term(), map() | MapSet.t(atom())) :: {:ok, field_name()} | :unknown
  def direct_root_field({:type, _meta, [expr, _type]}, aliases_or_root_aliases) do
    direct_root_field(expr, aliases_or_root_aliases)
  end

  def direct_root_field(
        {{:., _meta, [source, field]}, _call_meta, []},
        aliases_or_root_aliases
      )
      when is_atom(field) or is_binary(field) do
    if root_binding?(source, aliases_or_root_aliases) do
      {:ok, field}
    else
      :unknown
    end
  end

  def direct_root_field({:field, _meta, [source, field]}, aliases_or_root_aliases)
      when is_atom(field) or is_binary(field) do
    if root_binding?(source, aliases_or_root_aliases) do
      {:ok, field}
    else
      :unknown
    end
  end

  def direct_root_field(_expr, _aliases_or_root_aliases), do: :unknown

  @doc """
  Returns whether an expression contains any direct field reference.

  The expression is traversed recursively through tuples and lists. This helps
  checks reject field-to-field comparisons when only field-to-value predicates
  should count as explicit query constraints. Dynamic field expressions that use
  string field names are treated as field references too.
  """
  @spec field_reference?(term()) :: boolean()
  def field_reference?({{:., _meta, [_source, field]}, _call_meta, []})
      when is_atom(field) or is_binary(field),
      do: true

  def field_reference?({:field, _meta, [_source, field]})
      when is_atom(field) or is_binary(field),
      do: true

  def field_reference?(expr) when is_tuple(expr) do
    expr
    |> Tuple.to_list()
    |> field_reference?()
  end

  def field_reference?(expr) when is_list(expr), do: Enum.any?(expr, &field_reference?/1)
  def field_reference?(_expr), do: false

  @doc """
  Returns all fields declared by an Ecto schema module as a set.

  The caller is expected to pass a schema module. Use `root_schema/1` or
  `explicit_join_schema/1` first when the source may not be a schema.
  """
  @spec schema_fields(module()) :: MapSet.t(atom())
  def schema_fields(schema) do
    fields = schema.__schema__(:fields)

    MapSet.new(fields)
  end

  @doc """
  Returns whether `field` is declared by an Ecto schema module.

  The caller is expected to pass a schema module. Use this helper when a check
  needs to ignore configured fields that do not apply to the current schema.
  """
  @spec schema_field?(module(), atom()) :: boolean()
  def schema_field?(schema, field), do: field in schema.__schema__(:fields)

  defp query_branches(query, branch_path) do
    [{branch_path, query} | combination_branches(query, branch_path)]
  end

  defp combination_branches(%{combinations: combinations}, branch_path)
       when is_list(combinations) do
    combinations
    |> Enum.with_index()
    |> Enum.flat_map(fn
      {{combination_operation, combination_query}, combination_index} ->
        combination_path = [{combination_operation, combination_index} | branch_path]
        query_branches(combination_query, combination_path)

      {_combination, _combination_index} ->
        []
    end)
  end

  defp combination_branches(_query, _branch_path), do: []

  defp combination_path_entry({operation, index}), do: %{operation: operation, index: index}

  defp source_queries(%{from: %{source: source}}), do: subquery_source_queries(source)
  defp source_queries(_query), do: []

  defp join_queries(%{joins: joins}) when is_list(joins) do
    Enum.flat_map(joins, fn
      %{source: source} -> subquery_source_queries(source)
      _join -> []
    end)
  end

  defp join_queries(_query), do: []

  defp cte_queries(%{with_ctes: %{queries: queries}}) when is_list(queries) do
    Enum.flat_map(queries, fn
      {_name, _opts, query} -> [query]
      _cte -> []
    end)
  end

  defp cte_queries(_query), do: []

  defp combination_queries(%{combinations: combinations}) when is_list(combinations) do
    Enum.flat_map(combinations, fn
      {_operation, query} -> [query]
      _combination -> []
    end)
  end

  defp combination_queries(_query), do: []

  defp expression_queries(query) do
    Enum.flat_map(@expression_subquery_fields, fn field ->
      query
      |> Map.get(field)
      |> expression_subqueries()
    end)
  end

  defp expression_subqueries(expressions) when is_list(expressions) do
    Enum.flat_map(expressions, &expression_subqueries/1)
  end

  defp expression_subqueries({_name, expression}), do: expression_subqueries(expression)

  defp expression_subqueries(%{subqueries: subqueries}) when is_list(subqueries) do
    Enum.flat_map(subqueries, &subquery_source_queries/1)
  end

  defp expression_subqueries(_expression), do: []

  defp subquery_source_queries(%{__struct__: Ecto.SubQuery, query: query}), do: [query]
  defp subquery_source_queries(_source), do: []

  defp field(source, field, aliases) do
    case binding_index(source, aliases) do
      {:ok, binding_index} -> {:ok, {binding_index, field}}
      :unknown -> :unknown
    end
  end

  defp root_binding?({:&, _meta, [0]}, _aliases_or_root_aliases), do: true

  defp root_binding?({:as, _meta, [name]}, %MapSet{} = root_aliases) when is_atom(name) do
    MapSet.member?(root_aliases, name)
  end

  defp root_binding?({:as, _meta, [name]}, aliases) when is_atom(name) and is_map(aliases) do
    Map.get(aliases, name) == 0
  end

  defp root_binding?(_expr, _aliases_or_root_aliases), do: false
end
