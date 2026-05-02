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

      Repo.all(query, bylaw: [left_join_where_predicates: [validate: false]])

  Supported options:

      [
        left_join_where_predicates: [
          validate: true
        ]
      ]

    * `:validate` - explicit `false` disables the check. Defaults to `true`.

  The check is static and intentionally supports a small, tested subset of
  Ecto's query AST. It detects direct left-join binding fields in comparisons,
  `in` predicates, bare predicates, and `not is_nil(field)`. It does not try to
  prove predicates hidden inside fragments, subqueries, or arbitrary functions.
  Null-preserving anti-join predicates such as `is_nil(left_binding.id)` are
  allowed.
  """

  @behaviour Bylaw.Ecto.Query.Check

  alias Bylaw.Ecto.Query.Issue

  @comparison_ops [:==, :!=, :>, :>=, :<, :<=]
  @left_join_quals [:left, :left_lateral]

  @type check_opts :: list({:validate, boolean()})
  @type opts :: list({:left_join_where_predicates, check_opts()})
  @type field_set :: list(atom())
  @type rejection_map :: %{optional(non_neg_integer()) => MapSet.t(atom())}

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec name() :: :left_join_where_predicates
  def name, do: :left_join_where_predicates

  @doc """
  Validates left-join `where` predicates for a prepared Ecto query.

  The operation is kept as issue metadata. This check applies the same query
  validation to all `c:Ecto.Repo.prepare_query/3` operations.
  """

  @impl Bylaw.Ecto.Query.Check
  @spec validate(Bylaw.Ecto.Query.Check.operation(), Bylaw.Ecto.Query.Check.query(), opts()) ::
          Bylaw.Ecto.Query.Check.result()
  def validate(operation, query, opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      check_opts = check_opts!(opts)
      validate_query(operation, query, check_opts)
    else
      raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  def validate(_operation, _query, opts) do
    raise ArgumentError, "expected opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp check_opts!(opts) do
    opts
    |> Keyword.get(name(), [])
    |> normalize_check_opts!()
  end

  defp normalize_check_opts!(opts) when is_list(opts) do
    if Keyword.keyword?(opts) do
      Enum.each(opts, &validate_check_opt!/1)
      opts
    else
      raise ArgumentError,
            "expected #{inspect(name())} opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  defp normalize_check_opts!(opts) do
    raise ArgumentError,
          "expected #{inspect(name())} opts to be a keyword list, got: #{inspect(opts)}"
  end

  defp validate_check_opt!({:validate, _value}), do: :ok

  defp validate_check_opt!({key, _value}) do
    raise ArgumentError, "unknown #{inspect(name())} option: #{inspect(key)}"
  end

  defp enabled?(opts), do: Keyword.get(opts, :validate, true) != false

  defp validate_query(operation, query, check_opts) do
    if enabled?(check_opts) do
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
    aliases = query_aliases(query)

    query
    |> Map.get(:wheres, [])
    |> Enum.reduce(nil, fn where, branches ->
      expr_branches = rejection_branches_in_expr(Map.get(where, :expr), aliases)

      case Map.get(where, :op, :and) do
        :or -> concat_branches(branches, expr_branches)
        _op -> merge_branch_rejections(branches, expr_branches)
      end
    end)
    |> case do
      nil -> [%{}]
      branches -> branches
    end
  end

  defp query_aliases(%{aliases: aliases}) when is_map(aliases), do: aliases
  defp query_aliases(_query), do: %{}

  defp rejection_branches_in_expr({:and, _meta, [left, right]}, aliases) do
    merge_branch_rejections(
      rejection_branches_in_expr(left, aliases),
      rejection_branches_in_expr(right, aliases)
    )
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
    merge_branch_rejections(
      rejection_branches_in_negated_expr(left, aliases),
      rejection_branches_in_negated_expr(right, aliases)
    )
  end

  defp rejection_branches_in_negated_expr({:not, _meta, [expr]}, aliases) do
    rejection_branches_in_expr(expr, aliases)
  end

  defp rejection_branches_in_negated_expr(expr, aliases) do
    [rejecting_fields_in_negated_predicate(expr, aliases)]
  end

  defp merge_branch_rejections(nil, branches), do: branches

  defp merge_branch_rejections(left_branches, right_branches) do
    for left <- left_branches, right <- right_branches do
      merge_rejection_maps(left, right)
    end
  end

  defp concat_branches(nil, branches), do: branches
  defp concat_branches(left_branches, right_branches), do: left_branches ++ right_branches

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

  defp direct_fields({{:., _meta, [source, field]}, _call_meta, []}, aliases)
       when is_atom(field) do
    source
    |> source_binding_index(aliases)
    |> field_map(field)
  end

  defp direct_fields({:field, _meta, [source, field]}, aliases) when is_atom(field) do
    source
    |> source_binding_index(aliases)
    |> field_map(field)
  end

  defp direct_fields(_expr, _aliases), do: %{}

  defp source_binding_index({:&, _meta, [binding_index]}, _aliases)
       when is_integer(binding_index) do
    binding_index
  end

  defp source_binding_index({:as, _meta, [name]}, aliases) when is_atom(name) do
    Map.get(aliases, name, :unknown)
  end

  defp source_binding_index(_source, _aliases), do: :unknown

  defp field_map(binding_index, field) when is_integer(binding_index) do
    %{binding_index => MapSet.new([field])}
  end

  defp field_map(_binding_index, _field), do: %{}

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
