defmodule Bylaw.Credo.Check.Testing.NoSleepInTests do
  @moduledoc """
  Avoid sleeping in tests.

  ## Examples

  Avoid:

        test "sends a reminder" do
          Reminders.schedule(user, in: 10)
          Process.sleep(50)
          assert Reminders.sent?(user)
        end

  Prefer:

        test "sends a reminder" do
          Reminders.schedule(user, in: 10, notify: self())
          assert_receive {:reminder_sent, ^user}
        end


  A sleep guesses how long something takes. Guess too short and the test
  fails at random; guess too long and every run pays for it. Wait on a message
  with `assert_receive`, or pass the time in explicitly (for example as an
  argument or a fixture timestamp) instead of waiting for the clock.

  Both `Process.sleep/1` and `:timer.sleep/1` are reported in `*_test.exs`
  files.

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
          {Bylaw.Credo.Check.Testing.NoSleepInTests, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    tags: [:testing],
    explanations: [check: @moduledoc]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    if test_file?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_file?(filename) do
    String.ends_with?(filename, "_test.exs")
  end

  # Process.sleep(...)
  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:Process]}, :sleep]}, meta, _args} =
           ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line] || 0, "Process.sleep") | issues]}
  end

  # :timer.sleep(...)
  defp traverse({{:., _dot_meta, [:timer, :sleep]}, meta, _args} = ast, issues, issue_meta) do
    {ast, [issue_for(issue_meta, meta[:line] || 0, ":timer.sleep") | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Avoid `#{trigger}` in tests - it makes tests slow and flaky. " <>
          "Wait on a message with `assert_receive`, or pass the time in explicitly " <>
          "instead of waiting for the clock.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
