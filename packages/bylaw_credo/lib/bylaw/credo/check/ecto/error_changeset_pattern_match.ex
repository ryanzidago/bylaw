defmodule Bylaw.Credo.Check.Ecto.ErrorChangesetPatternMatch do
  @moduledoc """
  Match changeset errors explicitly when handling tagged `{:error, ...}`
  results.

  ## Examples

  Avoid:

        case Accounts.create_user(attrs) do
          {:ok, user} -> user
          {:error, changeset} -> changeset
        end
  Notes:
  A bare `{:error, changeset}` pattern only communicates a variable name.
  It does not prove the error value is an Ecto changeset, so readers have
  to inspect the called function before they know what the branch handles.
  Prefer:

        case Accounts.create_user(attrs) do
          {:ok, user} -> user
          {:error, %Ecto.Changeset{} = changeset} -> changeset
        end

  The struct match documents the expected error shape at the branch that
  handles it, and it prevents unrelated `{:error, reason}` values from
  being treated like changesets.

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
          {Bylaw.Credo.Check.Ecto.ErrorChangesetPatternMatch, []}
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

  @changeset_var_names ~w(changeset cs)a
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse({:case, _meta, [_condition, [do: clauses]]} = ast, issues, issue_meta)
       when is_list(clauses) do
    {ast, find_issues_in_clauses(clauses, issue_meta) ++ issues}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp find_issues_in_clauses(clauses, issue_meta) do
    Enum.flat_map(clauses, fn
      {:->, meta, [[pattern], _body]} ->
        if bare_error_changeset_pattern?(pattern) do
          [issue_for(issue_meta, meta[:line] || 0)]
        else
          []
        end

      _other ->
        []
    end)
  end

  defp bare_error_changeset_pattern?({:error, {var_name, _meta, nil}})
       when var_name in @changeset_var_names,
       do: true

  defp bare_error_changeset_pattern?(_other), do: false

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Use `{:error, %Changeset{} = changeset}` instead of `{:error, changeset}` to make the type explicit.",
      trigger: "{:error, changeset}",
      line_no: line_no
    )
  end
end
