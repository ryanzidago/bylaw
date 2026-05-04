defmodule Bylaw.Credo.Check.UseBylawSchema do
  @moduledoc """
  Enforces `use Bylaw.Schema` instead of `use Ecto.Schema`.

  `Bylaw.Schema` provides project defaults for UUIDv7 keys and UTC timestamps.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :design,
    explanations: [
      check: """
      `use Ecto.Schema` should not be used directly. Use `use Bylaw.Schema` instead.

      ## Why?

      `Bylaw.Schema` provides project-specific defaults:
      - UUIDv7 primary keys
      - UUIDv7 foreign keys
      - UTC datetime timestamps with microsecond precision

      ## Examples

      Bad:
      ```elixir
      defmodule MyApp.User do
        use Ecto.Schema

        schema "users" do
          field :name, :string
        end
      end
      ```

      Good:
      ```elixir
      defmodule MyApp.User do
        use Bylaw.Schema

        schema "users" do
          field :name, :string
        end
      end
      ```
      """
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    filename = source_file.filename

    if excluded_file?(filename) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp excluded_file?(filename) do
    String.ends_with?(filename, "lib/bylaw/schema.ex")
  end

  defp traverse(
         {:use, meta, [{:__aliases__, _alias_meta, [:Ecto, :Schema]} | _rest]} = ast,
         issues,
         issue_meta
       ) do
    line_no = meta[:line] || 0
    {ast, [issue_for(issue_meta, line_no) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message: "Use `use Bylaw.Schema` instead of `use Ecto.Schema`.",
      trigger: "use Ecto.Schema",
      line_no: line_no
    )
  end
end
