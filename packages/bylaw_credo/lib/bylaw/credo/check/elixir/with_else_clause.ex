defmodule Bylaw.Credo.Check.Elixir.WithElseClause do
  @moduledoc """
  Prefer adding an explicit `else` clause to every `with` expression.

  ## Examples

  Avoid:

        with {:ok, user} <- fetch_user(id) do
          {:ok, user.name}
        end

  Prefer:

        with {:ok, user} <- fetch_user(id) do
          {:ok, user.name}
        else
          {:error, error} -> {:error, error}
        end

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
          {Bylaw.Credo.Check.Elixir.WithElseClause, []}
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

  @doc false
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
