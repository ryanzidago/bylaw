defmodule Bylaw.Credo.Check.NoCatchAllInWithElse do
  @moduledoc """
  Disallows catch-all patterns in `with` else clauses.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Prefer explicit pattern matches in `with` else clauses over catch-all variables.

      Each `else` branch should match a specific pattern so that success and failure
      paths are clearly separated.

      This should be refactored:

          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            error -> error
          end

      Into this:

          with {:ok, user} <- fetch_user(id) do
            {:ok, user}
          else
            {:error, error} -> {:error, error}
          end
      """
    ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:with, _meta, arguments} = ast, ctx) do
    case find_catch_all_clause(arguments) do
      nil -> {ast, ctx}
      {line, trigger} -> {ast, put_issue(ctx, issue_for(ctx, line, trigger))}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp find_catch_all_clause(arguments) do
    case List.last(arguments) do
      block when is_list(block) ->
        if Keyword.keyword?(block) and Keyword.has_key?(block, :else) do
          block
          |> Keyword.get(:else)
          |> List.wrap()
          |> Enum.find_value(&catch_all_clause?/1)
        end

      _non_keyword_block ->
        nil
    end
  end

  defp catch_all_clause?({:->, meta, [[pattern], _body]}) do
    if bare_variable?(pattern) do
      name = variable_name(pattern)
      {meta[:line], to_string(name)}
    end
  end

  defp catch_all_clause?(_clause), do: nil

  defp bare_variable?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp bare_variable?(_pattern), do: false

  defp variable_name({name, _meta, _context}), do: name

  defp issue_for(ctx, line, trigger) do
    format_issue(
      ctx,
      message:
        "Avoid catch-all patterns in `with` else clauses. " <>
          "Use explicit pattern matches like `{:error, error}` instead of `#{trigger}`.",
      trigger: trigger,
      line_no: line
    )
  end
end
