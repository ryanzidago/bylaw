defmodule Bylaw.Credo.Check.Elixir.SafeDateTimeComparison do
  @moduledoc """
  Avoid direct comparison operators on values that look like dates or times.

  ## Examples

  Avoid:

        ~U[2026-01-26 10:00:00Z] > cutoff_at
        start_date <= ~D[2026-01-26]

  Prefer:

        DateTime.after?(entry.inserted_at, cutoff_at)
        Date.compare(start_date, end_date) in [:lt, :eq]


  Elixir's term ordering can compare structs even when the comparison is
  not the domain comparison you meant. Date and time types have comparison
  functions that encode the correct semantics.

  Use `compare/2`, `before?/2`, or `after?/2` from the relevant date/time
  module. Ecto `where` clauses are ignored because query comparisons are
  translated by Ecto instead of using Elixir term ordering.

  ## Options

  This check has no configurable options. It reports only comparisons involving
  explicit date/time sigils.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.SafeDateTimeComparison, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    tags: [:correctness],
    explanations: [check: @moduledoc]

  @comparison_operators [:==, :!=, :<, :>, :<=, :>=]
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    ecto_query_lines = collect_ecto_query_lines(source_file)

    Credo.Code.prewalk(
      source_file,
      &traverse(&1, &2, issue_meta, ecto_query_lines)
    )
  end

  defp collect_ecto_query_lines(source_file) do
    Credo.Code.prewalk(source_file, &collect_query_lines/2, MapSet.new())
  end

  defp collect_query_lines({:from, _meta, _args} = ast, acc) do
    {ast, MapSet.union(acc, extract_lines_from_ast(ast))}
  end

  defp collect_query_lines({:|>, _meta, [_left, {:where, _where_meta, _where_args}]} = ast, acc) do
    {ast, MapSet.union(acc, extract_lines_from_ast(ast))}
  end

  defp collect_query_lines({:where, _meta, _args} = ast, acc) do
    {ast, MapSet.union(acc, extract_lines_from_ast(ast))}
  end

  defp collect_query_lines({:where, _predicate} = ast, acc) do
    {ast, MapSet.union(acc, extract_lines_from_ast(ast))}
  end

  defp collect_query_lines(ast, acc), do: {ast, acc}

  defp extract_lines_from_ast(ast) do
    ast
    |> Macro.prewalk(MapSet.new(), fn
      {_name, meta, _args} = node, acc when is_list(meta) ->
        case Keyword.get(meta, :line) do
          nil -> {node, acc}
          line -> {node, MapSet.put(acc, line)}
        end

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp traverse({op, meta, [left, right]} = ast, issues, issue_meta, ecto_query_lines)
       when op in @comparison_operators do
    line_no = meta[:line] || 0

    cond do
      MapSet.member?(ecto_query_lines, line_no) ->
        {ast, issues}

      should_report_comparison?(left, right) ->
        {ast, [issue_for(issue_meta, line_no, op) | issues]}

      true ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _ecto_query_lines), do: {ast, issues}

  defp should_report_comparison?(left, right) do
    datetime_literal?(left) or datetime_literal?(right)
  end

  defp datetime_literal?({sigil, _meta, _args})
       when sigil in [:sigil_U, :sigil_D, :sigil_T, :sigil_N],
       do: true

  defp datetime_literal?(_node), do: false

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Avoid using #{trigger} for date/time comparison. Use compare/2, before?/2, or after?/2 instead.",
      trigger: to_string(trigger),
      line_no: line_no
    )
  end
end
