defmodule Bylaw.Credo.Check.Warning.NoTestsInTestDir do
  @moduledoc """
  Flags tests kept under `test/` instead of colocated with implementation.
  """

  use Credo.Check, base_priority: :higher, category: :warning

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
