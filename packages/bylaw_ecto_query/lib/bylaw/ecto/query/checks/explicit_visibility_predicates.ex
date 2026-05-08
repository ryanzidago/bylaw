defmodule Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates do
  @moduledoc """
  Validates that configured visibility-sensitive fields are explicitly constrained.

  This check is about query explicitness, not visibility correctness. Callers
  configure the schema fields that affect record visibility or lifecycle in
  their application, such as `:deleted_at`, `:archived_at`, `:hidden_at`,
  `:status`, `:state`, or `:published_at`. Bylaw only verifies that queries
  against configured schemas mention those fields in supported root `where`
  predicates.

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:schemas` - list of `{schema, fields: fields}` tuples. Defaults to `[]`.

  ## Examples

  Bad:

      from post in Post,
        where: post.organisation_id == ^organisation_id

  Why this is bad:

  If `Post` is configured with `fields: [:deleted_at]`, this query does not say
  whether soft-deleted rows should be visible. The visibility decision is left
  implicit.

  Better:

      from post in Post,
        where: post.organisation_id == ^organisation_id,
        where: is_nil(post.deleted_at)

  Why this is better:

  The root predicate states the visibility decision directly: only rows without
  `deleted_at` are requested.

  Better when archived rows are intentional:

      from post in Post,
        where: post.archived_at <= ^cutoff

  Limitations:

  This check verifies explicitness, not visibility correctness. It accepts
  supported root predicates that mention configured fields, but it cannot prove
  predicates hidden inside fragments or subqueries.

  The check is static. It accepts configured root fields when they appear
  directly in `where` expressions, including `is_nil(field)`, `not is_nil(field)`,
  bare field predicates, comparisons against values or parameters, and `in`
  predicates whose right side has no field references. Field-to-field
  comparisons are not treated as explicit constraints. It cannot prove visibility
  fields hidden inside raw SQL fragments or subqueries. Combination queries such
  as `union`, `union_all`, `except`, and `intersect` validate the parent query
  and every combination branch independently.

  When the root query schema is not configured, the check returns `:ok`.
  Configured fields that do not exist on the root schema are ignored. If no
  applicable configured fields remain, the check returns `:ok`.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Branches
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @comparison_ops [:==, :!=, :>, :>=, :<, :<=]

  @type schema_config :: {module(), list({:fields, list(atom())})}
  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:schemas, list(schema_config())}
          )
  @type opts :: check_opts()

  @doc """
  Validates explicit visibility-sensitive root `where` predicates.

  The operation is kept as issue metadata. This check applies the same query
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    opts = CheckOptions.keyword_list!(opts, "opts")
    check_opts = CheckOptions.normalize!(opts, [:schemas, :validate])

    if CheckOptions.enabled?(check_opts) do
      validate_enabled(operation, query, check_opts)
    else
      :ok
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_enabled(operation, query, check_opts) do
    schema_configs = fetch_schema_configs!(check_opts)

    query
    |> Introspection.query_branches()
    |> Enum.flat_map(&issues_for_branch(operation, &1, schema_configs))
    |> result()
  end

  defp issues_for_branch(operation, {branch_path, query}, schema_configs) do
    with {:ok, schema} <- Introspection.root_schema(query),
         {:ok, configured_fields} <- configured_fields(schema_configs, schema),
         applicable_fields = applicable_fields(schema, configured_fields),
         false <- Enum.empty?(applicable_fields) do
      issues_for_applicable_branch(
        operation,
        query,
        schema,
        configured_fields,
        applicable_fields,
        branch_path
      )
    else
      _not_applicable -> []
    end
  end

  defp issues_for_applicable_branch(
         operation,
         query,
         schema,
         configured_fields,
         applicable_fields,
         branch_path
       ) do
    field_branches = where_field_branches(query)
    fields = Branches.guaranteed_sets(field_branches)
    missing = missing_fields(applicable_fields, field_branches)

    if Enum.empty?(missing) do
      []
    else
      [
        issue(
          operation,
          schema,
          configured_fields,
          applicable_fields,
          fields,
          missing,
          branch_path
        )
      ]
    end
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp fetch_schema_configs!(opts) do
    opts
    |> Keyword.get(:schemas, [])
    |> normalize_schema_configs!()
  end

  defp normalize_schema_configs!(schemas) when is_list(schemas) do
    Enum.map(schemas, &normalize_schema_config!/1)
  end

  defp normalize_schema_configs!(schemas) do
    raise ArgumentError,
          "expected :schemas to be a list of {schema, fields: fields} tuples, got: #{inspect(schemas)}"
  end

  defp normalize_schema_config!({schema, schema_opts})
       when is_atom(schema) and is_list(schema_opts) do
    cond do
      not function_exported?(schema, :__schema__, 1) ->
        raise ArgumentError,
              "expected configured schema to be an Ecto schema, got: #{inspect(schema)}"

      not Keyword.keyword?(schema_opts) ->
        raise ArgumentError,
              "expected schema options for #{inspect(schema)} to be a keyword list, got: #{inspect(schema_opts)}"

      true ->
        Enum.each(schema_opts, &validate_schema_opt!(schema, &1))
        {schema, fields: fetch_fields!(schema, schema_opts)}
    end
  end

  defp normalize_schema_config!(schema_config) do
    raise ArgumentError,
          "expected :schemas to contain {schema, fields: fields} tuples, got: #{inspect(schema_config)}"
  end

  defp validate_schema_opt!(_schema, {:fields, _value}), do: :ok

  defp validate_schema_opt!(schema, {key, _value}) do
    raise ArgumentError, "unknown option for schema #{inspect(schema)}: #{inspect(key)}"
  end

  defp fetch_fields!(schema, opts) do
    case Keyword.fetch(opts, :fields) do
      {:ok, fields} ->
        normalize_fields!(schema, fields)

      :error ->
        raise ArgumentError, "missing required :fields option for schema #{inspect(schema)}"
    end
  end

  defp normalize_fields!(_schema, []) do
    raise ArgumentError,
          "expected :fields to be a non-empty list of atoms, got: []"
  end

  defp normalize_fields!(_schema, fields) when is_list(fields) do
    fields
    |> CheckOptions.non_empty_atoms!(:fields)
    |> Enum.uniq()
  end

  defp normalize_fields!(_schema, fields) do
    raise ArgumentError,
          "expected :fields to be a non-empty list of atoms, got: #{inspect(fields)}"
  end

  defp configured_fields(schema_configs, schema) do
    case Enum.find(schema_configs, fn {configured_schema, _opts} ->
           configured_schema == schema
         end) do
      {^schema, fields: fields} -> {:ok, fields}
      nil -> :unknown
    end
  end

  defp applicable_fields(schema, fields) do
    schema_fields = Introspection.schema_fields(schema)
    Enum.filter(fields, &MapSet.member?(schema_fields, &1))
  end

  defp where_field_branches(query) when is_map(query) do
    aliases = Introspection.aliases(query)

    branches =
      query
      |> Map.get(:wheres, [])
      |> Enum.reduce(nil, fn where, branches ->
        expr_branches = field_branches_in_expr(Map.get(where, :expr), aliases)

        case Map.get(where, :op, :and) do
          :or -> Branches.concat(branches, expr_branches)
          _op -> Branches.merge(branches, expr_branches, &MapSet.union/2)
        end
      end)

    case branches do
      nil -> [MapSet.new()]
      branches -> branches
    end
  end

  defp where_field_branches(_query), do: [MapSet.new()]

  defp field_branches_in_expr({:and, _meta, [left, right]}, aliases) do
    left_branches = field_branches_in_expr(left, aliases)
    right_branches = field_branches_in_expr(right, aliases)

    Branches.merge(left_branches, right_branches, &MapSet.union/2)
  end

  defp field_branches_in_expr({:or, _meta, [left, right]}, aliases) do
    field_branches_in_expr(left, aliases) ++ field_branches_in_expr(right, aliases)
  end

  defp field_branches_in_expr({:not, _meta, [{:is_nil, _is_nil_meta, [expr]}]}, aliases) do
    [root_field_set(expr, aliases)]
  end

  defp field_branches_in_expr({:not, _meta, [{op, _op_meta, [_left, _right]} = expr]}, aliases)
       when op in @comparison_ops or op == :in do
    field_branches_in_expr(expr, aliases)
  end

  defp field_branches_in_expr({:not, _meta, [expr]}, aliases) do
    [root_field_set(expr, aliases)]
  end

  defp field_branches_in_expr({:is_nil, _meta, [expr]}, aliases) do
    [root_field_set(expr, aliases)]
  end

  defp field_branches_in_expr({op, _meta, [left, right]}, aliases) when op in @comparison_ops do
    fields = comparison_root_fields(left, right, aliases)

    [MapSet.new(fields)]
  end

  defp field_branches_in_expr({:in, _meta, [left, right]}, aliases) do
    if Introspection.field_reference?(right) do
      [MapSet.new()]
    else
      [root_field_set(left, aliases)]
    end
  end

  defp field_branches_in_expr(expr, aliases) do
    [root_field_set(expr, aliases)]
  end

  defp root_field_set(expr, aliases) do
    expr
    |> Introspection.root_fields(aliases)
    |> MapSet.new()
  end

  defp comparison_root_fields(left, right, aliases) do
    cond do
      Introspection.field_reference?(left) and Introspection.field_reference?(right) ->
        []

      Introspection.field_reference?(left) ->
        Introspection.root_fields(left, aliases)

      Introspection.field_reference?(right) ->
        Introspection.root_fields(right, aliases)

      true ->
        []
    end
  end

  defp missing_fields(fields, field_branches) do
    Enum.reject(fields, fn field ->
      Enum.all?(field_branches, &MapSet.member?(&1, field))
    end)
  end

  defp issue(
         operation,
         schema,
         configured_fields,
         applicable_fields,
         found_fields,
         missing,
         branch_path
       ) do
    %Issue{
      check: __MODULE__,
      message: message(missing),
      meta:
        Map.merge(
          %{
            operation: operation,
            root_schema: schema,
            configured_fields: configured_fields,
            applicable_fields: applicable_fields,
            missing_fields: missing,
            found_visibility_fields: found_visibility_fields(found_fields, applicable_fields)
          },
          Introspection.combination_path_meta(branch_path)
        )
    }
  end

  defp found_visibility_fields(found_fields, applicable_fields) do
    applicable_fields
    |> MapSet.new()
    |> MapSet.intersection(found_fields)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp message(missing) do
    "expected query to explicitly constrain visibility-sensitive fields: #{format_fields(missing)}"
  end

  defp format_fields(fields) do
    Enum.map_join(fields, ", ", &inspect/1)
  end
end
