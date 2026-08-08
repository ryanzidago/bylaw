defmodule Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst do
  @moduledoc """
  Prefer a single-row Repo read over loading every matching row and taking the
  first result in Elixir.

  `Repo.all` retrieves and materializes every match even when the caller needs
  only one row. `Repo.one` expresses the cardinality expectation at the Repo
  boundary, avoids unnecessary row transfer, and can surface an unexpected
  second match instead of silently discarding it.

  ## Examples

  Avoid:

      query
      |> Repo.all()
      |> List.first()

      query
      |> Repo.all()
      |> Enum.at(0)

      query
      |> Repo.all()
      |> hd()

  When the query is expected to return zero or one row, prefer:

      Repo.one(query)

  When the query intentionally selects the first row from an ordered result,
  preserve that intent in the query:

      query
      |> Ecto.Query.first()
      |> Repo.one()

  Use the bang variants when a missing row is exceptional. For primary-key
  lookups, prefer `Repo.get/2` or `Repo.get!/2`.

  ## Notes

  This check uses static AST analysis. It reports direct `Repo.all` and
  first-element selection with `List.first/1`, `Enum.at/2` with the literal
  index `0`, or `hd/1`, including piped forms. It cannot infer whether the
  caller expects uniqueness or an ordered first row. Other `Enum.at/2` indices
  are outside this check's scope because they express different offset and
  ordering semantics.

  ## Options

  This check has no check-specific options. Configure it with an empty option
  list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    tags: [:database, :performance],
    explanations: [
      check: @moduledoc
    ]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk(
         {:|>, _pipe_meta,
          [value, {{:., meta, [{:__aliases__, _aliases_meta, [:List]}, :first]}, _call_meta, []}]} =
           ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "List.first", value, false)}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:List]}, :first]}, _call_meta, [value]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "List.first", value, false)}
  end

  defp walk(
         {:|>, _pipe_meta,
          [value, {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, :at]}, _call_meta, [0]}]} =
           ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "Enum.at", value, false)}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, :at]}, _call_meta, [value, 0]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "Enum.at", value, false)}
  end

  defp walk({:|>, _pipe_meta, [value, {:hd, meta, []}]} = ast, ctx) do
    {ast, maybe_put_issue(ctx, meta, "hd", value, true)}
  end

  defp walk({:hd, meta, [value]} = ast, ctx) do
    {ast, maybe_put_issue(ctx, meta, "hd", value, true)}
  end

  defp walk(
         {:|>, _pipe_meta,
          [value, {{:., meta, [{:__aliases__, _aliases_meta, [:Kernel]}, :hd]}, _call_meta, []}]} =
           ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "Kernel.hd", value, true)}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:Kernel]}, :hd]}, _call_meta, [value]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, "Kernel.hd", value, true)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp maybe_put_issue(ctx, meta, trigger, value, raises_on_empty?) do
    if repo_all_expression?(value) do
      put_issue(ctx, issue_for(ctx, meta, trigger, raises_on_empty?))
    else
      ctx
    end
  end

  defp repo_all_expression?({{:., _dot_meta, [repo, :all]}, _call_meta, _arguments}),
    do: repo_module?(repo)

  defp repo_all_expression?({:|>, _pipe_meta, [_query, repo_all_stage]}),
    do: repo_all_stage?(repo_all_stage)

  defp repo_all_expression?(_other), do: false

  defp repo_all_stage?({{:., _dot_meta, [repo, :all]}, _call_meta, _arguments}),
    do: repo_module?(repo)

  defp repo_all_stage?(_other), do: false

  defp repo_module?({:__aliases__, _meta, aliases}), do: List.last(aliases) == :Repo
  defp repo_module?(_other), do: false

  defp issue_for(ctx, meta, trigger, raises_on_empty?) do
    repo_read =
      if raises_on_empty? do
        "`Repo.one!/1`"
      else
        "`Repo.one/1` or `Repo.one!/1`"
      end

    format_issue(
      ctx,
      message:
        "Prefer #{repo_read} when the query expects at most one row. " <>
          "For an ordered first row, use `Ecto.Query.first/1` followed by #{repo_read}. " <>
          "Use `Repo.get/2` or `Repo.get!/2` for primary-key lookups.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
