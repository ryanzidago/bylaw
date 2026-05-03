defmodule Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates do
  @moduledoc """
  Validates that `left_join` bindings are not null-rejected by root `where` predicates.

  A `where` predicate on a left-joined binding usually turns the join into an
  inner join because rows without a matching joined record have `NULL` values
  for that binding. Optional joined-record filters belong in the join `on`
  clause instead:

      from post in Post,
        left_join: comment in Comment,
        on: comment.post_id == post.id and comment.status == ^:published

  The check is enabled by default. A caller must explicitly set the query-level
  escape hatch to `false` to skip it:

      Repo.all(query, bylaw: [{Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates, validate: false}])

  Supported options:

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check is static and intentionally supports a small, tested subset of
  Ecto's query AST. It detects direct left-join binding fields in comparisons,
  `in` predicates, bare predicates, and `not is_nil(field)`. It does not try to
  prove predicates hidden inside fragments, subqueries, or arbitrary functions.
  Null-preserving anti-join predicates such as `is_nil(left_binding.id)` are
  allowed.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Branches
  alias Bylaw.Ecto.Query.CheckOptions
  alias Bylaw.Ecto.Query.Introspection
  alias Bylaw.Ecto.Query.Issue

  @comparison_ops [:==, :!=, :>, :>=, :<, :<=]
  @left_join_quals [:left, :left_lateral]

  @type check_opts :: list({:validate, boolean()})
  @type opts :: check_opts()
  @type field_set :: list(atom())
  @type rejection_map :: %{optional(non_neg_integer()) => MapSet.t(atom())}

  @doc """
  Validates left-join `where` predicates for a prepared Ecto query.

  The operation is kept as issue metadata. This check applies the same query
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate])

    validate_query(operation, query, check_opts)
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_query(operation, query, check_opts) do
    if CheckOptions.enabled?(check_opts) do
      validate_enabled(operation, query)
    else
      :ok
    end
  end

  defp validate_enabled(operation, query) do
    case issues(operation, query) do
      [] -> :ok
      [issue] -> {:error, issue}
      issues -> {:error, issues}
    end
  end

  defp issues(operation, query) when is_map(query) do
    branches = where_rejection_branches(query)

    query
    |> Map.get(:joins, [])
    |> Enum.with_index()
    |> Enum.flat_map(fn {join, join_index} ->
      binding_index = join_index + 1

      if left_join?(join) and null_rejected?(branches, binding_index) do
        [
          issue(
            operation,
            join,
            join_index,
            binding_index,
            rejecting_fields(branches, binding_index)
          )
        ]
      else
        []
      end
    end)
  end

  defp issues(_operation, _query), do: []

  defp left_join?(%{qual: qual}), do: qual in @left_join_quals
  defp left_join?(_join), do: false

  defp where_rejection_branches(query) do
    aliases = Introspection.aliases(query)

    branches =
      query
      |> Map.get(:wheres, [])
      |> Enum.reduce(nil, fn where, branches ->
        expr_branches = rejection_branches_in_expr(Map.get(where, :expr), aliases)

        case Map.get(where, :op, :and) do
          :or -> Branches.concat(branches, expr_branches)
          _op -> Branches.merge(branches, expr_branches, &merge_rejection_maps/2)
        end
      end)

    case branches do
      nil -> [%{}]
      branches -> branches
    end
  end

  defp rejection_branches_in_expr({:and, _meta, [left, right]}, aliases) do
    left_branches = rejection_branches_in_expr(left, aliases)
    right_branches = rejection_branches_in_expr(right, aliases)

    Branches.merge(left_branches, right_branches, &merge_rejection_maps/2)
  end

  defp rejection_branches_in_expr({:or, _meta, [left, right]}, aliases) do
    rejection_branches_in_expr(left, aliases) ++ rejection_branches_in_expr(right, aliases)
  end

  defp rejection_branches_in_expr({:not, _meta, [expr]}, aliases) do
    rejection_branches_in_negated_expr(expr, aliases)
  end

  defp rejection_branches_in_expr(expr, aliases) do
    [rejecting_fields_in_predicate(expr, aliases)]
  end

  defp rejection_branches_in_negated_expr({:and, _meta, [left, right]}, aliases) do
    rejection_branches_in_negated_expr(left, aliases) ++
      rejection_branches_in_negated_expr(right, aliases)
  end

  defp rejection_branches_in_negated_expr({:or, _meta, [left, right]}, aliases) do
    left_branches = rejection_branches_in_negated_expr(left, aliases)
    right_branches = rejection_branches_in_negated_expr(right, aliases)

    Branches.merge(left_branches, right_branches, &merge_rejection_maps/2)
  end

  defp rejection_branches_in_negated_expr({:not, _meta, [expr]}, aliases) do
    rejection_branches_in_expr(expr, aliases)
  end

  defp rejection_branches_in_negated_expr(expr, aliases) do
    [rejecting_fields_in_negated_predicate(expr, aliases)]
  end

  defp rejecting_fields_in_predicate({:is_nil, _meta, [_expr]}, _aliases), do: %{}

  defp rejecting_fields_in_predicate({op, _meta, [left, right]}, aliases)
       when op in [:==, :!=] do
    left
    |> direct_fields(aliases)
    |> merge_rejection_maps(direct_fields(right, aliases))
    |> merge_rejection_maps(false_is_nil_comparison_fields(op, left, right, aliases))
  end

  defp rejecting_fields_in_predicate({op, _meta, [left, right]}, aliases)
       when op in @comparison_ops or op == :in do
    left
    |> direct_fields(aliases)
    |> merge_rejection_maps(direct_fields(right, aliases))
  end

  defp rejecting_fields_in_predicate(expr, aliases) do
    direct_fields(expr, aliases)
  end

  defp rejecting_fields_in_negated_predicate({op, _meta, [left, right]}, aliases)
       when op in [:==, :!=] do
    left
    |> direct_fields(aliases)
    |> merge_rejection_maps(direct_fields(right, aliases))
    |> merge_rejection_maps(true_is_nil_comparison_fields(op, left, right, aliases))
  end

  defp rejecting_fields_in_negated_predicate({op, _meta, [left, right]}, aliases)
       when op in @comparison_ops or op == :in do
    left
    |> direct_fields(aliases)
    |> merge_rejection_maps(direct_fields(right, aliases))
  end

  defp rejecting_fields_in_negated_predicate({:is_nil, _meta, [expr]}, aliases) do
    direct_fields(expr, aliases)
  end

  defp rejecting_fields_in_negated_predicate(expr, aliases) do
    direct_fields(expr, aliases)
  end

  defp false_is_nil_comparison_fields(:==, left, false, aliases),
    do: nil_check_fields(left, aliases)

  defp false_is_nil_comparison_fields(:==, false, right, aliases),
    do: nil_check_fields(right, aliases)

  defp false_is_nil_comparison_fields(:!=, left, true, aliases),
    do: nil_check_fields(left, aliases)

  defp false_is_nil_comparison_fields(:!=, true, right, aliases),
    do: nil_check_fields(right, aliases)

  defp false_is_nil_comparison_fields(_op, _left, _right, _aliases), do: %{}

  defp true_is_nil_comparison_fields(:==, left, true, aliases),
    do: nil_check_fields(left, aliases)

  defp true_is_nil_comparison_fields(:==, true, right, aliases),
    do: nil_check_fields(right, aliases)

  defp true_is_nil_comparison_fields(:!=, left, false, aliases),
    do: nil_check_fields(left, aliases)

  defp true_is_nil_comparison_fields(:!=, false, right, aliases),
    do: nil_check_fields(right, aliases)

  defp true_is_nil_comparison_fields(_op, _left, _right, _aliases), do: %{}

  defp nil_check_fields({:is_nil, _meta, [expr]}, aliases), do: direct_fields(expr, aliases)
  defp nil_check_fields(_expr, _aliases), do: %{}

  defp direct_fields(expr, aliases) do
    case Introspection.field(expr, aliases) do
      {:ok, {binding_index, field}} -> field_map(binding_index, field)
      :unknown -> %{}
    end
  end

  defp field_map(binding_index, field) do
    %{binding_index => MapSet.new([field])}
  end

  defp merge_rejection_maps(left, right) do
    Map.merge(left, right, fn _binding_index, left_fields, right_fields ->
      MapSet.union(left_fields, right_fields)
    end)
  end

  defp null_rejected?(branches, binding_index) do
    Enum.all?(branches, &Map.has_key?(&1, binding_index))
  end

  @spec rejecting_fields(list(rejection_map()), pos_integer()) :: field_set()
  defp rejecting_fields(branches, binding_index) do
    branches
    |> Enum.reduce(MapSet.new(), fn branch, fields ->
      MapSet.union(fields, Map.get(branch, binding_index, MapSet.new()))
    end)
    |> MapSet.to_list()
    |> Enum.sort()
  end

  defp issue(operation, join, join_index, binding_index, fields) do
    %Issue{
      check: __MODULE__,
      message: message(binding_index, fields),
      meta: %{
        operation: operation,
        join_index: join_index,
        binding_index: binding_index,
        join_qual: Map.get(join, :qual),
        rejecting_where_fields: fields
      }
    }
  end

  defp message(binding_index, fields) do
    "expected left join binding #{binding_index} filters to stay in join on clauses; rejecting where fields: #{format_fields(fields)}"
  end

  defp format_fields(fields), do: Enum.map_join(fields, ", ", &inspect/1)
end
