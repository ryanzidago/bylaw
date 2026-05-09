defmodule Bylaw.Credo.Check.Ecto.NoAndInWhere do
  @moduledoc """
  Split combined Ecto `where` predicates into separate `where` clauses.

  ## Examples

  Avoid:

        User
        |> where([u], u.active and u.confirmed_at > ^cutoff)
        |> Repo.all()
  Notes:
  Packing multiple predicates into one `where` expression makes query
  composition harder. Separate clauses are easier to add, remove, reorder,
  and conditionally compose with helper functions.
  Prefer:

        User
        |> where([u], u.active)
        |> where([u], u.confirmed_at > ^cutoff)
        |> Repo.all()

  Each clause carries one constraint, which keeps incremental query
  building clear and makes diffs smaller when a predicate changes.

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
          {Bylaw.Credo.Check.Ecto.NoAndInWhere, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: @moduledoc
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:where, meta, arguments} = ast, issues, issue_meta) do
    issues =
      case where_expression(arguments) do
        nil ->
          issues

        expression ->
          if contains_and?(expression) do
            [issue_for(issue_meta, meta[:line] || 0) | issues]
          else
            issues
          end
      end

    {ast, issues}
  end

  defp traverse({:from, meta, arguments} = ast, issues, issue_meta) do
    issues =
      case from_where_expression(arguments) do
        nil ->
          issues

        expression ->
          if contains_and?(expression) do
            [issue_for(issue_meta, meta[:line] || 0) | issues]
          else
            issues
          end
      end

    {ast, issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp where_expression([_bindings, expression]), do: expression
  defp where_expression([expression]), do: expression
  defp where_expression(_arguments), do: nil

  defp from_where_expression([_queryable, options]) when is_list(options) do
    Keyword.get(options, :where)
  end

  defp from_where_expression(_arguments), do: nil

  defp contains_and?(ast) do
    ast
    |> Macro.prewalk(false, fn
      {:and, _meta, [_left, _right]} = node, _acc ->
        {node, true}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Do not use `and` inside Ecto `where` clauses. Prefer each clause to be its own `where`.",
      trigger: "and",
      line_no: line_no
    )
  end
end
