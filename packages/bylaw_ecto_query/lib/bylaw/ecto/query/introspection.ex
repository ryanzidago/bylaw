defmodule Bylaw.Ecto.Query.Introspection do
  @moduledoc false

  # Path from the root query into nested Ecto combination queries.
  @typedoc false
  @type branch_path :: list({atom(), non_neg_integer()})

  # Query branch paired with its path from the root query.
  @typedoc false
  @type query_branch :: {branch_path(), term()}

  # Field name extracted from an Ecto field expression.
  @typedoc false
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

  # The root schema comes from the query `from` source. Return `:unknown` for
  # schema-less sources, malformed values, non-query values, and modules that do
  # not expose Ecto schema reflection.
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

  # Association joins can encode application-specific behavior separately from
  # the visible join source, so checks that reason about direct explicit joins
  # skip them instead of treating them as plain schema joins.
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

  # Ecto stores named binding aliases as alias name => positional binding index.
  # Query values without an aliases map get an empty map so callers can avoid
  # special-casing schema-less or malformed query terms.
  @spec aliases(term()) :: map()
  def aliases(%{aliases: aliases}) when is_map(aliases), do: aliases
  def aliases(_query), do: %{}

  # Root aliases are alias names whose binding index is 0. Root-only checks pass
  # this set to field helpers when join bindings should be ignored.
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

  # Ecto stores set-operation branches under `combinations`. Checks that must
  # validate each branch independently use this path so issue metadata can point
  # back to the nested combination branch.
  @spec query_branches(term()) :: list(query_branch())
  def query_branches(query) do
    query
    |> query_branches([])
    |> Enum.map(fn {branch_path, branch_query} -> {Enum.reverse(branch_path), branch_query} end)
  end

  # Offset/order checks need to inspect immediate nested query references from
  # sources, joins, CTEs, combinations, and expression subqueries. Callers that
  # need full-depth traversal recurse over this result.
  @spec nested_queries(term()) :: list(term())
  def nested_queries(query) when is_map(query) do
    source_queries(query) ++
      join_queries(query) ++
      cte_queries(query) ++ combination_queries(query) ++ expression_queries(query)
  end

  def nested_queries(_query), do: []

  # Root branches omit metadata. Combination branches include a stable
  # `:combination_path` value suitable for issue metadata.
  @spec combination_path_meta(branch_path()) :: map()
  def combination_path_meta([]), do: %{}

  def combination_path_meta(branch_path) do
    %{combination_path: Enum.map(branch_path, &combination_path_entry/1)}
  end

  # Resolve positional binding expressions such as `&0` and named binding
  # expressions such as `as(:post)`. Missing or unresolved aliases return
  # `:unknown` instead of raising so checks can ignore unsupported shapes.
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

  # Resolve dot-field expressions (`post.status`) and dynamic field expressions
  # (`field(post, :status)`) to `{binding_index, field}`. Other expressions or
  # unresolved bindings return `:unknown`.
  @spec field(term(), map()) :: {:ok, {non_neg_integer(), atom()}} | :unknown
  def field({{:., _meta, [source, field]}, _call_meta, []}, aliases) when is_atom(field) do
    field(source, field, aliases)
  end

  def field({:field, _meta, [source, field]}, aliases) when is_atom(field) do
    field(source, field, aliases)
  end

  def field(_expr, _aliases), do: :unknown

  # Like `field/2`, but succeeds only for root binding references. The second
  # argument accepts either the full aliases map or the precomputed root alias
  # set from `root_aliases/1`.
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

  # Convenience wrapper for checks that accumulate root field lists from many
  # expressions and want unsupported expressions to contribute no fields.
  @spec root_fields(term(), map() | MapSet.t(atom())) :: list(atom())
  def root_fields(expr, aliases_or_root_aliases) do
    case root_field(expr, aliases_or_root_aliases) do
      {:ok, field} -> [field]
      :unknown -> []
    end
  end

  # `root_field/2` intentionally returns only atom fields. This variant also
  # accepts binary field names and unwraps `type/2` so configured checks can
  # decide how to normalize root field references.
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

  # Predicate checks use this to distinguish field-to-value constraints from
  # field-to-field comparisons, including nested expressions and dynamic
  # field/2 references.
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

  # Callers are expected to pass a known Ecto schema module, usually after
  # `root_schema/1` or `explicit_join_schema/1` has accepted the source.
  @spec schema_fields(module()) :: MapSet.t(atom())
  def schema_fields(schema) do
    fields = schema.__schema__(:fields)

    MapSet.new(fields)
  end

  # Use this when configured fields should be ignored for schemas that do not
  # declare them.
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
