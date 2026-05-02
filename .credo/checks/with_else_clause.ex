defmodule Bylaw.Credo.Check.Readability.WithElseClause do
  @moduledoc """
  Requires `with` expressions to define an explicit `else` clause.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Prefer adding an explicit `else` clause to every `with` expression.

      This should be refactored:

          with {:ok, user} <- fetch_user(id) do
            {:ok, user.name}
          end

      Into this:

          with {:ok, user} <- fetch_user(id) do
            {:ok, user.name}
          else
            error -> error
          end
      """
    ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:with, meta, arguments} = ast, ctx) do
    case missing_else_clause?(arguments) do
      true -> {ast, put_issue(ctx, issue_for(ctx, meta))}
      false -> {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp missing_else_clause?(arguments) do
    case List.last(arguments) do
      block when is_list(block) ->
        Keyword.keyword?(block) and Keyword.has_key?(block, :do) and
          not Keyword.has_key?(block, :else)

      _other ->
        false
    end
  end

  defp issue_for(ctx, meta) do
    format_issue(
      ctx,
      message: "Add an `else` clause to `with` expressions to make error handling explicit.",
      trigger: "with",
      line_no: meta[:line]
    )
  end
end
