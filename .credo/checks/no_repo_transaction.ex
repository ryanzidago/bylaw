defmodule Bylaw.Credo.Check.Warning.NoRepoTransaction do
  @moduledoc """
  Discourages calling `Repo.transaction/1,2` directly. Use `Repo.transact/1,2` instead.
  """

  use Credo.Check, category: :warning, base_priority: :higher

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, aliases}, :transaction]}, meta, _args} =
           ast,
         issues,
         issue_meta
       ) do
    if List.last(aliases) == :Repo do
      {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Avoid calling `Repo.transaction` directly. Use `Repo.transact` instead (Ecto 3.13+).",
      trigger: "transaction",
      line_no: line_no
    )
  end
end
