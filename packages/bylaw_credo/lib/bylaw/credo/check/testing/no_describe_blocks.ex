defmodule Bylaw.Credo.Check.Testing.NoDescribeBlocks do
  @moduledoc """
  Avoid `describe` blocks in test files.

  ## Examples

  Avoid:

      describe "creating a user" do
        test "returns the user" do
          assert create_user().active?
        end
      end

  Prefer:

      test "creating a user returns an active user" do
        assert create_user().active?
      end

  ## Notes

  Descriptive standalone test names make each test's behavior visible without
  relying on an enclosing block. When a suite grows, split it into multiple
  focused test files instead of grouping unrelated behavior with `describe`.

  Path exclusions are matched against the source filename and are intended for
  generated files or temporary migration areas.

  The check uses static AST analysis, so dynamic code generation and
  macro-expanded code may fall outside its signal.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoDescribeBlocks,
           [
             excluded_paths: ["test/support/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:excluded_paths` - Paths containing any configured string are skipped.
    Use this for test files that are intentionally being migrated.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoDescribeBlocks, []}
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
        Paths containing any configured string are skipped. Use this for test
        files that are intentionally being migrated.
        """
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if test_file?(source_file.filename) and not excluded?(source_file.filename, excluded_paths) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_file?(filename) do
    String.ends_with?(filename, "_test.exs")
  end

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &String.contains?(filename, &1))
  end

  defp traverse({:describe, meta, [_name, [do: _body]]} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
  end

  defp traverse(
         {{:., _dot_meta, [_module, :describe]}, meta, [_name, [do: _body]]} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Avoid `describe` blocks in test files. Give tests descriptive standalone names and split a growing suite into multiple focused test files.",
      trigger: "describe",
      line_no: line_no
    )
  end
end
