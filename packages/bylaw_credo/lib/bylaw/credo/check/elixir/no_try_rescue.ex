defmodule Bylaw.Credo.Check.Elixir.NoTryRescue do
  @moduledoc """
  Avoid `try/rescue` and `try/catch` for ordinary control flow.

  ### Bad

      try do
        Accounts.fetch_user!(id)
      rescue
        Ecto.NoResultsError -> {:error, :not_found}
      end

  ### Why?

  Exceptions hide expected failure modes and make the successful path look
  more reliable than it is. They also push error handling away from the
  function contract.

  ### Better

      case Accounts.fetch_user(id) do
        {:ok, user} -> {:ok, user}
        {:error, :not_found} -> {:error, :not_found}
      end

  Prefer functions that return explicit values and handle those values with
  pattern matching. `try/after` without `rescue` or `catch` is still allowed
  for resource cleanup.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: @moduledoc
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:try, meta, [clauses]} = ast, issues, issue_meta) do
    has_rescue = Keyword.has_key?(clauses, :rescue)
    has_catch = Keyword.has_key?(clauses, :catch)

    case has_rescue or has_catch do
      true -> {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
      false -> {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Try blocks should not be used. Prefer pattern matching with `case` or explicit validation instead.",
      trigger: "try",
      line_no: line_no
    )
  end
end
