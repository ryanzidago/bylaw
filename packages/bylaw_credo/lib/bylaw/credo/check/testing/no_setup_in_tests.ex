defmodule Bylaw.Credo.Check.Testing.NoSetupInTests do
  @moduledoc """
  Avoid `setup` and `setup_all` blocks in test modules.

  ## Examples

  Avoid:

        setup do
          {:ok, user: create_user()}
        end

        test "shows user", %{user: user} do
          assert user.active?
        end
  Notes:
  Shared setup hides the inputs a test needs and encourages unrelated tests
  to depend on the same fixture shape. `setup_all` also creates shared data
  that can make ordering and isolation problems harder to see.
  Prefer:

        test "shows user" do
          user = create_user()
          assert user.active?
        end

  Keep each test's data close to the assertion. `setup :verify_on_exit!` is
  allowed because it supports mock verification rather than shared fixture
  construction.

  ## Notes

  Path exclusions are matched against the source filename and are intended for generated files or temporary migration areas.

  The check uses static AST analysis, so dynamic code generation and macro-expanded code may fall outside its signal.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoSetupInTests,
           [
             excluded_paths: ["test/support/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:excluded_paths` - Paths containing any configured string are skipped. Use this for shared test case modules that intentionally define setup callbacks.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoSetupInTests, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: """
        Paths containing any configured string are skipped. Use this for shared
        test case modules that intentionally define setup callbacks.
        """
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if excluded?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &String.contains?(filename, &1))
  end

  defp traverse({:setup, _meta, [:verify_on_exit!]} = ast, issues, _issue_meta), do: {ast, issues}

  defp traverse({:setup, meta, _args} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, meta[:line] || 0, "setup") | issues]}
  end

  defp traverse({:setup_all, meta, _args} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, meta[:line] || 0, "setup_all") | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message: "Avoid using `#{trigger}` blocks. Each test should have its own setup.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
