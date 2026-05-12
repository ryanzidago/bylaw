defmodule Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates do
  @moduledoc """
  Validates that configured visibility-sensitive fields are explicitly constrained.

  This check is about query explicitness, not visibility correctness. Callers
  configure the root fields that affect record visibility or lifecycle in their
  application, such as `:deleted_at`, `:archived_at`, `:hidden_at`, `:status`,
  `:state`, or `:published_at`. Bylaw only verifies that matching queries
  mention those fields in supported root `where` predicates.

  ## Examples

  Bad:

      from(Post, as: :post)
      |> where([post: p], p.organization_id == ^organization_id)

  Why this is bad:

  If `Post` is covered by `rules: [where: [ecto_schemas: [Post]], fields:
  [:deleted_at]]`, this query does not say whether soft-deleted rows should be
  visible. The visibility decision is left implicit.

  Better:

      from(Post, as: :post)
      |> where([post: p], p.organization_id == ^organization_id)
      |> where([post: p], is_nil(p.deleted_at))

  Why this is better:

  The root predicate states the visibility decision directly: only rows without
  `deleted_at` are requested.

  Better when archived rows are intentional:

      from(Post, as: :post)
      |> where([post: p], p.archived_at <= ^cutoff)

  ## Notes

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

  When the root query uses an Ecto schema, configured fields are narrowed to
  fields that exist on that schema. If no applicable configured fields remain,
  the check returns `:ok`. Schema-less sources can still be validated because
  there is no schema reflection signal.

  ## Options

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:rules` - required rule keyword list or non-empty list of rule keyword
      lists. A single-rule shorthand such as `rules: [fields: [:deleted_at]]`
      is normalized to one rule.
    * `:fields` - required non-empty list of visibility-sensitive root fields
      inside each rule.
    * `:where` and `:except` - optional rule matchers for scoping rules.
      Matchers use plural keys with list values, such as `ecto_schemas: [Post]`,
      `tables: ["posts"]`, `db_schemas: ["tenant_a"]`, and
      `operations: [:all]`.

  Example check spec:

      {Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
       rules: [where: [ecto_schemas: [Post]], fields: [:deleted_at, :archived_at]]}

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.Ecto.Query`.
  See `Bylaw.Ecto.Query` for the full `c:Ecto.Repo.prepare_query/3` setup.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Branches
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue
  alias Bylaw.Ecto.Query.RuleOptions

  @comparison_ops [:==, :!=, :>, :>=, :<, :<=]

  @typedoc false
  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:rules, keyword() | list(keyword())}
          )
  @typedoc false
  @type opts :: check_opts()

  @doc """
  Implements the `Bylaw.Ecto.Query.Check` validation callback.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.keyword_list!(opts, "opts")
    CheckOptions.validate_allowed_keys!(check_opts, [:validate, :rules])

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
    rules =
      RuleOptions.fetch_rules!(
        check_opts,
        :explicit_visibility_predicates,
        [:fields],
        &rule_payload!/1
      )

    query
    |> Introspection.query_branches()
    |> Enum.flat_map(&issues_for_branch(operation, &1, rules))
    |> result()
  end

  defp rule_payload!(opts) do
    %{fields: opts |> CheckOptions.fetch_non_empty_atoms!(:fields) |> Enum.uniq()}
  end

  defp issues_for_branch(operation, {branch_path, query}, rules) do
    operation
    |> RuleOptions.matching_rules(query, rules)
    |> Enum.flat_map(&issues_for_rule(operation, query, &1, branch_path))
  end

  defp issues_for_rule(operation, query, rule, branch_path) do
    case Introspection.root_schema(query) do
      {:ok, schema} ->
        applicable_fields = applicable_fields(schema, rule.fields)

        if Enum.empty?(applicable_fields) do
          []
        else
          issues_for_applicable_branch(
            operation,
            query,
            schema,
            rule.fields,
            applicable_fields,
            branch_path
          )
        end

      :unknown ->
        issues_for_applicable_branch(
          operation,
          query,
          nil,
          rule.fields,
          rule.fields,
          branch_path
        )
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
