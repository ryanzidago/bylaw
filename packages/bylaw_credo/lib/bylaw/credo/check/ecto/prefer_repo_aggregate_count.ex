defmodule Bylaw.Credo.Check.Ecto.PreferRepoAggregateCount do
  @moduledoc """
  Prefer `Repo.aggregate(queryable, :count)` over loading rows with `Repo.all`
  and counting them in memory.

  ## Examples

  Avoid:

        Repo.all(query) |> Enum.count()
        Enum.count(Repo.all(query))
        query |> Repo.all() |> length()
  Prefer:

        Repo.aggregate(query, :count)

  Prefer `Repo.exists?/1` or `not Repo.exists?/1` over comparing
  `Repo.aggregate(query, :count)` to `0` or `1` for existence checks.
  Avoid:

        Repo.aggregate(query, :count) > 0
        Repo.aggregate(query, :count) == 0
  Prefer:

        Repo.exists?(query)
        not Repo.exists?(query)

  ## Notes

  This check uses static AST analysis, so it favors clear source-level patterns over runtime behavior.

  ## Options

  This check has no check-specific options. Configure it with an empty option list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.PreferRepoAggregateCount, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: @moduledoc
    ]

  @comparison_operators [:>, :>=, :<, :<=, :==, :===, :!=, :!==]
  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:length, meta, [value]} = ast, ctx) do
    {ast, maybe_put_issue(ctx, meta, "length", value)}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:Kernel]}, :length]}, _call_meta, [value]} =
           ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "Kernel.length", value)}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, :count]}, _call_meta, [value]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "Enum.count", value)}
  end

  defp walk({:|>, _pipe_meta, [value, {:length, meta, []}]} = ast, ctx) do
    {ast, maybe_put_issue(ctx, meta, "length", value)}
  end

  defp walk(
         {:|>, _pipe_meta,
          [
            value,
            {{:., meta, [{:__aliases__, _aliases_meta, [:Kernel]}, :length]}, _call_meta, []}
          ]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "Kernel.length", value)}
  end

  defp walk(
         {:|>, _pipe_meta,
          [value, {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, :count]}, _call_meta, []}]} =
           ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "Enum.count", value)}
  end

  defp walk({op, meta, [left, right]} = ast, ctx) when op in @comparison_operators do
    case existence_issue(ctx, meta, op, left, right) do
      nil -> {ast, ctx}
      issue -> {ast, put_issue(ctx, issue)}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp maybe_put_issue(ctx, meta, trigger, value) do
    if repo_all_expression?(value) do
      put_issue(ctx, issue_for(ctx, meta, trigger))
    else
      ctx
    end
  end

  defp repo_all_expression?({{:., _dot_meta, [repo, :all]}, _call_meta, _args}),
    do: repo_module?(repo)

  defp repo_all_expression?({:|>, _pipe_meta, [_value, repo_all_stage]}),
    do: repo_all_stage?(repo_all_stage)

  defp repo_all_expression?(_other), do: false

  defp repo_aggregate_count_expression?(
         {{:., _dot_meta, [repo, :aggregate]}, _call_meta, arguments}
       )
       when is_list(arguments) do
    repo_module?(repo) and aggregate_count_arguments?(arguments)
  end

  defp repo_aggregate_count_expression?({:|>, _pipe_meta, [_value, aggregate_stage]}),
    do: aggregate_count_stage?(aggregate_stage)

  defp repo_aggregate_count_expression?(_other), do: false

  defp repo_all_stage?({{:., _dot_meta, [repo, :all]}, _call_meta, _args}), do: repo_module?(repo)
  defp repo_all_stage?(_other), do: false

  defp aggregate_count_stage?({{:., _dot_meta, [repo, :aggregate]}, _call_meta, arguments})
       when is_list(arguments) do
    repo_module?(repo) and aggregate_count_stage_arguments?(arguments)
  end

  defp aggregate_count_stage?(_other), do: false

  defp aggregate_count_arguments?([_queryable, :count]), do: true
  defp aggregate_count_arguments?([_queryable, :count, _field]), do: true
  defp aggregate_count_arguments?(_arguments), do: false

  defp aggregate_count_stage_arguments?([:count]), do: true
  defp aggregate_count_stage_arguments?([:count, _field]), do: true
  defp aggregate_count_stage_arguments?(_arguments), do: false

  defp repo_module?({:__aliases__, _meta, aliases}), do: List.last(aliases) == :Repo
  defp repo_module?(_other), do: false

  defp existence_issue(ctx, meta, op, left, right) do
    cond do
      repo_aggregate_count_expression?(left) and existence_comparison?(op, right) ->
        issue_for_exists(ctx, meta, Atom.to_string(op))

      repo_aggregate_count_expression?(right) and reversed_existence_comparison?(op, left) ->
        issue_for_exists(ctx, meta, Atom.to_string(op))

      true ->
        nil
    end
  end

  defp existence_comparison?(:>, 0), do: true
  defp existence_comparison?(:>=, 1), do: true
  defp existence_comparison?(:!=, 0), do: true
  defp existence_comparison?(:!==, 0), do: true
  defp existence_comparison?(:==, 0), do: true
  defp existence_comparison?(:===, 0), do: true
  defp existence_comparison?(:<, 1), do: true
  defp existence_comparison?(:<=, 0), do: true
  defp existence_comparison?(_op, _value), do: false

  defp reversed_existence_comparison?(:<, 0), do: true
  defp reversed_existence_comparison?(:<=, 1), do: true
  defp reversed_existence_comparison?(:!=, 0), do: true
  defp reversed_existence_comparison?(:!==, 0), do: true
  defp reversed_existence_comparison?(:==, 0), do: true
  defp reversed_existence_comparison?(:===, 0), do: true
  defp reversed_existence_comparison?(:>, 1), do: true
  defp reversed_existence_comparison?(:>=, 0), do: true
  defp reversed_existence_comparison?(_op, _value), do: false

  defp issue_for(ctx, meta, trigger) do
    format_issue(
      ctx,
      message:
        "Prefer `Repo.aggregate(queryable, :count)` over counting rows loaded by `Repo.all(...)` with `#{trigger}`.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end

  defp issue_for_exists(ctx, meta, trigger) do
    format_issue(
      ctx,
      message:
        "Prefer `Repo.exists?/1` or `not Repo.exists?/1` over count-based existence checks with `Repo.aggregate(..., :count)`.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
