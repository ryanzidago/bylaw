defmodule Bylaw.Credo.Check.Ecto.UseMyAppSchema do
  @moduledoc """
  `use Ecto.Schema` should not be used directly. Use your app schema module instead.

  ## Examples

  Notes:
  An app schema module, such as `MyApp.Schema`, can provide project-specific
  schema defaults:
  - primary key conventions
  - foreign key conventions
  - timestamp precision and type conventions
  Avoid:
  ```elixir
  defmodule MyApp.User do
      use Ecto.Schema

      schema "users" do
        field :name, :string
      end
  end
  ```
  Prefer:
  ```elixir
  defmodule MyApp.User do
      use MyApp.Schema

      schema "users" do
        field :name, :string
      end
  end
  ```

  ## Notes

  This check uses static AST analysis, so it favors clear source-level patterns over runtime behavior.
  Since each application chooses its own schema wrapper module, files ending in
  `/schema.ex` are treated as wrapper modules and are not reported.

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
          {Bylaw.Credo.Check.Ecto.UseMyAppSchema, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :design,
    explanations: [
      check: @moduledoc
    ]

  @doc false
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
    String.ends_with?(filename, "/schema.ex")
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
      message:
        "Use your app schema module, such as `use MyApp.Schema`, instead of `use Ecto.Schema`.",
      trigger: "use Ecto.Schema",
      line_no: line_no
    )
  end
end
