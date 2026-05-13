defmodule Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates do
  @moduledoc """
  Validates that `left_join` bindings are not null-rejected by root `where` predicates.

  A `where` predicate on a left-joined binding usually turns the join into an
  inner join because rows without a matching joined record have `NULL` values
  for that binding. Optional joined-record filters belong in the join `on`
  clause instead.

  ## Examples

  Bad:

      from(Post, as: :post)
      |> join(:left, [post: p], c in Comment,
        as: :comment,
        on: c.post_id == p.id
      )
      |> where([comment: c], c.status == ^:published)

  Why this is bad:

  Rows without a matching comment have `NULL` values for the joined binding.
  The root `where` predicate rejects those rows, so the left join behaves like
  an inner join.

  Better:

      from(Post, as: :post)
      |> join(:left, [post: p], c in Comment,
        as: :comment,
        on: c.post_id == p.id and c.status == ^:published
      )

  Why this is better:

  The optional comment filter stays in the join predicate. Posts are preserved
  even when no matching published comment exists.

  ## Notes

  This check detects supported direct field predicates on left-join bindings. It
  does not prove predicates hidden inside fragments, subqueries, or arbitrary
  functions.

  ## Options

    * `:validate` - explicit `false` disables this check. It can be used in the
      repo-wide check list or in call-site overrides passed to
      `Bylaw.Ecto.Query.validate/4`.

  Run globally with defaults:

      Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates

  Run only for matching rule scopes:

      {Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates,
       rules: [
         [where: [ecto_schemas: [Post]]],
         [where: [tables: ["posts"]]]
       ]}

  This check has no check-specific rule options.

  ## Usage

  Add this module to the explicit check list passed through `Bylaw.Ecto.Query`.
  See `Bylaw.Ecto.Query` for the full `c:Ecto.Repo.prepare_query/3` setup.

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
  alias Bylaw.Ecto.Query.RuleOptions

  @comparison_ops [:==, :!=, :>, :>=, :<, :<=]
  @left_join_quals [:left, :left_lateral]

  @typedoc false
  @type check_opts :: list({:validate, boolean()})
  @typedoc false
  @type opts :: check_opts()
  @typedoc false
  @type field_set :: list(atom())
  @typedoc false
  @type rejection_map :: %{optional(non_neg_integer()) => MapSet.t(atom())}

  @doc """
  Implements the `Bylaw.Ecto.Query.Check` validation callback.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    check_opts = CheckOptions.normalize!(opts, [:validate, :rules])

    validate_query(operation, query, check_opts)
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_query(operation, query, check_opts) do
    if CheckOptions.enabled?(check_opts) and
         RuleOptions.scoped?(check_opts, :left_join_where_predicates, operation, query) do
      validate_enabled(operation, query)
    else
      :ok
    end
  end

  defp validate_enabled(operation, query) do
    case issues(operation, query) do
      [] -> :ok
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
