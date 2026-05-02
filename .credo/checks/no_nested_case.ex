defmodule Bylaw.Credo.Check.Refactor.NoNestedCase do
  @moduledoc """
  Disallows nested `case` statements.

  Nested `case` blocks can usually be flattened into a single `with` expression,
  which is easier to read and reason about.
  """

  use Credo.Check, base_priority: :high, category: :refactor

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:case, _meta, [_expr, [do: clauses]]} = ast, issues, issue_meta) do
    new_issues =
      clauses
      |> List.wrap()
      |> Enum.flat_map(&find_nested_cases(&1, issue_meta))

    {ast, new_issues ++ issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp find_nested_cases({:->, _arrow_meta, [_pattern, body]}, issue_meta) do
    collect_nested_cases(body, issue_meta)
  end

  defp find_nested_cases(_other, _issue_meta), do: []

  defp collect_nested_cases({:__block__, _block_meta, exprs}, issue_meta) do
    case List.last(exprs) do
      {:case, meta, _case_args} -> [issue_for(issue_meta, meta[:line] || 0)]
      _other -> []
    end
  end

  defp collect_nested_cases({:case, meta, _case_args}, issue_meta) do
    [issue_for(issue_meta, meta[:line] || 0)]
  end

  defp collect_nested_cases(_other, _issue_meta), do: []

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Nested `case` detected. Flatten ok/error branching into a single `with` with `<-` clauses " <>
          "and an explicit `else` clause.",
      trigger: "case",
      line_no: line_no
    )
  end
end
