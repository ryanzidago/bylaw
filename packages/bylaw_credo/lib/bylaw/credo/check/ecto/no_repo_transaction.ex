defmodule Bylaw.Credo.Check.Ecto.NoRepoTransaction do
  @moduledoc """
  Use `Repo.transact/1,2` instead of calling `Repo.transaction/1,2`
  directly.

  ## Examples

  Avoid:

        Repo.transaction(fn ->
          create_user!(attrs)
          create_audit_event!(attrs)
        end)

  Prefer:

        Repo.transact(fn ->
          create_user!(attrs)
          create_audit_event!(attrs)
        end)

  ## Notes

  `Repo.transaction/1,2` is deprecated in Ecto 3.13 in favor of
  `Repo.transact/1,2`. Keeping deprecated calls around makes future Ecto
  upgrades noisier and leaves new transactional code on the old API.

  `Repo.transact/1,2` communicates the preferred Ecto API directly and
  keeps transaction call sites off the deprecated API.

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
          {Bylaw.Credo.Check.Ecto.NoRepoTransaction, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    category: :warning,
    base_priority: :higher,
    explanations: [
      check: @moduledoc
    ]

  @doc false
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
      message: "`Repo.transaction` is deprecated in Ecto 3.13+. Use `Repo.transact` instead.",
      trigger: "transaction",
      line_no: line_no
    )
  end
end
