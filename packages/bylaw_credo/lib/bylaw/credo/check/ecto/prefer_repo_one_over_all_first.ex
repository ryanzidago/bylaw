defmodule Bylaw.Credo.Check.Ecto.PreferRepoOneOverAllFirst do
  @moduledoc """
  Prefer a single-row Repo read over loading every matching row and taking the
  first result in Elixir.

  ## Examples

  Avoid:

      query
      |> Repo.all()
      |> List.first()

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
  `List.first` combinations, including piped forms, but cannot infer whether
  the caller expects uniqueness or an ordered first row.

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
    explanations: [
      check: @moduledoc
    ]

  @message "Prefer `Repo.one/1` or `Repo.one!/1` when the query expects at most one row. " <>
             "For an ordered first row, use `Ecto.Query.first/1` followed by `Repo.one/1`. " <>
             "Use `Repo.get/2` or `Repo.get!/2` for primary-key lookups."

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
    {ast, maybe_put_issue(ctx, meta, value)}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:List]}, :first]}, _call_meta, [value]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, value)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp maybe_put_issue(ctx, meta, value) do
    if repo_all_expression?(value) do
      put_issue(ctx, issue_for(ctx, meta))
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

  defp issue_for(ctx, meta) do
    format_issue(
      ctx,
      message: @message,
      trigger: "List.first",
      line_no: meta[:line]
    )
  end
end
