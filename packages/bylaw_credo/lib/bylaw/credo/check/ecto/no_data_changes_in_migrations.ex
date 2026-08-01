defmodule Bylaw.Credo.Check.Ecto.NoDataChangesInMigrations do
  @moduledoc """
  Keep Ecto migrations focused on database schema changes.

  ## Examples

  Avoid changing rows from a migration:

      def up do
        Repo.update_all(Account, set: [status: :active])
        execute("DELETE FROM expired_sessions")
      end

  Prefer a reviewed data-migration script or explicit release task that can
  batch, throttle, observe, retry, and resume the work safely:

      mix run priv/repo/data_migrations/backfill_account_statuses.exs

  ## Why

  Ecto migrations normally run while holding the migration lock and inside a
  DDL transaction. Row mutations and backfills can make that transaction
  unexpectedly long, block application traffic, and couple operational data
  work to schema deployment. Separate data migrations can be run at the right
  time with the operational safeguards their volume requires.

  This check is a best-effort automated guideline, not an airtight boundary.
  It reports direct calls to common `Repo` mutation functions and literal SQL
  passed to `execute/1,2` when it begins with `INSERT`, `UPDATE`, `DELETE`, or
  `MERGE`. It intentionally does not guess about helper functions, dynamic SQL,
  or application-specific `Repo` wrappers.

  If a data change genuinely belongs in a schema migration, disable the check
  locally with Credo and document why the exception is safe.

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
          {Bylaw.Credo.Check.Ecto.NoDataChangesInMigrations, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: @moduledoc
    ]

  @repo_mutations [
    :insert,
    :insert!,
    :insert_all,
    :insert_or_update,
    :insert_or_update!,
    :update,
    :update!,
    :update_all,
    :delete,
    :delete!,
    :delete_all
  ]

  @data_change_message "Keep schema migrations focused on DDL. " <>
                         "Move row changes to a reviewed data-migration script or explicit " <>
                         "release task so they can be batched, observed, retried, and resumed."

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    if migration_file?(source_file) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, aliases}, operation]}, meta, _args} =
           ast,
         issues,
         issue_meta
       )
       when operation in @repo_mutations do
    if List.last(aliases) == :Repo do
      trigger = Enum.join(aliases, ".") <> "." <> Atom.to_string(operation)
      {ast, [issue_for(issue_meta, meta, trigger) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse({:execute, meta, [sql | _rest]} = ast, issues, issue_meta)
       when is_binary(sql) do
    case data_mutation_statement(sql) do
      nil -> {ast, issues}
      statement -> {ast, [issue_for(issue_meta, meta, statement) | issues]}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp data_mutation_statement(sql) do
    case Regex.run(~r/^\s*(INSERT|UPDATE|DELETE|MERGE)\b/i, sql, capture: :all_but_first) do
      [statement] -> String.upcase(statement)
      nil -> nil
    end
  end

  defp migration_file?(source_file) do
    String.contains?(source_file.filename, "/priv/repo/migrations/") or
      String.starts_with?(source_file.filename, "priv/repo/migrations/")
  end

  defp issue_for(issue_meta, meta, trigger) do
    format_issue(
      issue_meta,
      message: @data_change_message,
      trigger: trigger,
      line_no: meta[:line] || 0
    )
  end
end
