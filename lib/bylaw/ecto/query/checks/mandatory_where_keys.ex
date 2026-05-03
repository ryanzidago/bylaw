defmodule Bylaw.Ecto.Query.Checks.MandatoryWhereKeys do
  @moduledoc """
  Validates that a query has a root `where` predicate referencing configured keys.

  This is useful for tenant boundaries where every query should include a
  predicate for fields such as `:organisation_id` or `:user_id`.

  For repo-wide enforcement, include this module in `Bylaw.Ecto.Query.validate/3`.
  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for repo wiring.

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [{Bylaw.Ecto.Query.Checks.MandatoryWhereKeys, validate: false}])

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.
    * `:keys` - required non-empty list of field names when the check runs.
    * `:match` - `:any` or `:all`. Defaults to `:any`.

  The check is static. It accepts configured root fields directly in `==` and `in`
  predicates inside `where` expressions, but it cannot prove fields hidden
  inside raw SQL fragments. Combination queries such as `union`, `union_all`,
  `except`, and `intersect` validate the parent query and every combination
  branch independently.

  When the root query uses an Ecto schema, the configured keys are first narrowed
  to fields that exist on that schema. If none of the configured keys exist, the
  check is not applicable and returns `:ok`. Schema-less sources are still
  validated because there is no schema reflection signal.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Branches
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @type match :: :any | :all
  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:keys, list(atom())}
            | {:match, match()}
          )
  @type opts :: check_opts()

  @doc """
  Validates mandatory root `where` predicates for a prepared Ecto query.

  The operation is kept as issue metadata. This check applies the same query
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:keys, :match, :validate])

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
    keys = CheckOptions.fetch_non_empty_atoms!(check_opts, :keys)

    query
    |> Introspection.query_branches()
    |> Enum.flat_map(&issues_for_branch(operation, &1, check_opts, keys))
    |> result()
  end

  defp issues_for_branch(operation, {branch_path, query}, check_opts, keys) do
    case applicable_keys(query, keys) do
      [] ->
        []

      applicable_keys ->
        issues_for_applicable_branch(operation, query, check_opts, applicable_keys, branch_path)
    end
  end

  defp issues_for_applicable_branch(operation, query, check_opts, applicable_keys, branch_path) do
    match = CheckOptions.match!(check_opts)
    field_branches = where_field_branches(query)
    fields = Branches.guaranteed_sets(field_branches)
    missing = missing_keys(applicable_keys, field_branches, match)

    if Enum.empty?(missing) do
      []
    else
      [issue(operation, applicable_keys, fields, missing, match, branch_path)]
    end
  end

  defp result([]), do: :ok
  defp result([issue]), do: {:error, issue}
  defp result(issues), do: {:error, issues}

  defp applicable_keys(query, keys) do
    case Introspection.root_schema(query) do
      {:ok, schema} ->
        schema_fields = Introspection.schema_fields(schema)
        Enum.filter(keys, &MapSet.member?(schema_fields, &1))

      :unknown ->
        keys
    end
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

  defp field_branches_in_expr({:==, _meta, [left, right]}, aliases) do
    fields = equality_root_fields(left, right, aliases)

    [root_field_set(fields)]
  end

  defp field_branches_in_expr({:in, _meta, [left, right]}, aliases) do
    if Introspection.field_reference?(right) do
      [MapSet.new()]
    else
      [root_field_set(left, aliases)]
    end
  end

  defp field_branches_in_expr(_expr, _aliases), do: [MapSet.new()]

  defp root_field_set(expr, aliases) do
    expr
    |> Introspection.root_fields(aliases)
    |> MapSet.new()
  end

  defp root_field_set(fields), do: MapSet.new(fields)

  defp equality_root_fields(left, right, aliases) do
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

  defp missing_keys(keys, field_branches, :any) do
    if Enum.all?(field_branches, &branch_has_any_key?(&1, keys)), do: [], else: keys
  end

  defp missing_keys(keys, field_branches, :all) do
    Enum.reject(keys, fn key ->
      Enum.all?(field_branches, &MapSet.member?(&1, key))
    end)
  end

  defp branch_has_any_key?(fields, keys), do: Enum.any?(keys, &MapSet.member?(fields, &1))

  defp issue(operation, keys, fields, missing, match, branch_path) do
    found_where_keys =
      fields
      |> MapSet.to_list()
      |> Enum.sort()

    %Issue{
      check: __MODULE__,
      message: message(keys, missing, match),
      meta:
        Map.merge(
          %{
            operation: operation,
            keys: keys,
            match: match,
            missing_keys: missing,
            found_where_keys: found_where_keys
          },
          Introspection.combination_path_meta(branch_path)
        )
    }
  end

  defp message(keys, _missing, :any) do
    "expected query to filter by at least one of: #{format_keys(keys)}"
  end

  defp message(_keys, missing, :all) do
    "expected query to filter by all mandatory keys; missing: #{format_keys(missing)}"
  end

  defp format_keys(keys) do
    Enum.map_join(keys, ", ", &inspect/1)
  end
end
