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

  Prefer:

        test "shows user" do
          user = create_user()
          assert user.active?
        end


  Self-contained tests keep the facts that explain an expected result next to
  the assertion. Shared setup moves those facts into an implicit API tied to
  the test module, so readers and reviewers must reconstruct the scenario from
  multiple locations. It also makes tests harder to move, and shared fixture
  state can accumulate stale or accidental dependencies.

  Some repetition is worthwhile when it makes each scenario and its important
  differences visible. Explicit domain helpers are still useful when the test
  calls them to request the state it needs. `setup :verify_on_exit!` is allowed
  because it supports mock verification rather than shared fixture construction.

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
    category: :design,
    tags: [:testing],
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
