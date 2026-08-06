defmodule Bylaw.Credo.Check.Ecto.PreferOrderByOverRepoAllEnumSort do
  @moduledoc """
  Prefer ordering Ecto queries in the database over sorting rows in memory.

  Database-side ordering avoids materializing all matching rows before sorting
  them in Elixir, reducing application memory and work. It also lets the
  database combine ordering with filtering, limits, and indexes before rows
  cross the database boundary.

  ## Examples

  Avoid:

      query
      |> Repo.all()
      |> Enum.sort()

      query
      |> Repo.all()
      |> Enum.sort_by(& &1.inserted_at)

  Prefer adding `order_by` to the query before calling `Repo.all`.

  This check reports only direct `Repo.all` followed by `Enum.sort` or
  `Enum.sort_by`. Sorting after an intermediate transformation may have
  different semantics and is outside this check's scope.

  This check uses static AST analysis and cannot infer the equivalent
  `order_by` expression, so it does not provide an automatic rewrite.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk(
         {:|>, _outer_pipe_meta,
          [
            {:|>, _inner_pipe_meta, [_query, repo_all]},
            {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, function]}, _call_meta, args}
          ]} = ast,
         ctx
       )
       when function in [:sort, :sort_by] do
    {ast, maybe_put_issue(ctx, meta, repo_all, function, args)}
  end

  defp walk(
         {:|>, _pipe_meta,
          [
            repo_all,
            {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, function]}, _call_meta, args}
          ]} =
           ast,
         ctx
       )
       when function in [:sort, :sort_by] do
    {ast, maybe_put_issue(ctx, meta, repo_all, function, args)}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, function]}, _call_meta,
          [repo_all | args]} = ast,
         ctx
       )
       when function in [:sort, :sort_by] do
    {ast, maybe_put_issue(ctx, meta, repo_all, function, args)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp maybe_put_issue(ctx, meta, repo_all, function, args) do
    if repo_all_expression?(repo_all) and valid_sort_arity?(function, args) do
      put_issue(ctx, issue_for(ctx, meta, function))
    else
      ctx
    end
  end

  defp valid_sort_arity?(:sort, []), do: true
  defp valid_sort_arity?(:sort_by, [_mapper]), do: true
  defp valid_sort_arity?(_function, _args), do: false

  defp repo_all_expression?({{:., _dot_meta, [repo, :all]}, _call_meta, _args}),
    do: repo_module?(repo)

  defp repo_all_expression?(_other), do: false

  defp repo_module?({:__aliases__, _meta, aliases}), do: List.last(aliases) == :Repo
  defp repo_module?(_other), do: false

  defp issue_for(ctx, meta, function) do
    format_issue(
      ctx,
      message:
        "Prefer using `order_by` in the Ecto query instead of sorting `Repo.all` results with `Enum.#{function}`.",
      trigger: "Enum.#{function}",
      line_no: meta[:line]
    )
  end
end
