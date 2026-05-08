defmodule Bylaw.Credo.Check.Testing.NoTestsInTestDir do
  @moduledoc """
  Keep test files colocated with the implementation they cover instead of
  storing them under a separate top-level `test/` directory.

  ### Bad

      test/bylaw/example_test.exs

  ### Why?

  A separate test tree makes it harder to find the tests for a module and
  easier to move implementation without noticing stale or missing coverage.

  ### Better

      lib/bylaw/example.ex
      lib/bylaw/example_test.exs

  Colocation keeps behavior and coverage near each other, which makes
  focused changes and reviews cheaper.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: @moduledoc
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    filename = source_file.filename

    if String.starts_with?(filename, "test/") and String.ends_with?(filename, "_test.exs") do
      [issue_for(source_file, params, filename)]
    else
      []
    end
  end

  defp issue_for(source_file, _params, filename) do
    format_issue(
      source_file,
      message:
        "Test file should be colocated with implementation, not stored under test/: #{filename}",
      trigger: filename,
      line_no: 1
    )
  end
end
