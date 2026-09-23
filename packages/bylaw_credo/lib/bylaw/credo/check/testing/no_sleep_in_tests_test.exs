defmodule Bylaw.Credo.Check.Testing.NoSleepInTestsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.NoSleepInTests

  test "reports Process.sleep in a test file" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        Process.sleep(1100)
        assert true
      end
    end
    """
    |> to_source_file("lib/example_test.exs")
    |> run_check(NoSleepInTests)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Process.sleep"
      assert issue.line_no == 5

      assert issue.message ==
               "Avoid `Process.sleep` in tests - it makes tests slow and flaky. " <>
                 "Wait on a message with `assert_receive`, or pass the time in explicitly " <>
                 "instead of waiting for the clock."
    end)
  end

  test "reports :timer.sleep in a test file" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        :timer.sleep(100)
        assert true
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSleepInTests)
    |> assert_issue(fn issue ->
      assert issue.trigger == ":timer.sleep"
      assert issue.line_no == 5
    end)
  end

  test "reports every sleep in a test file" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        Process.sleep(10)
        :timer.sleep(10)
        Process.sleep(10)
        assert true
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSleepInTests)
    |> assert_issues(fn issues ->
      line_numbers =
        issues
        |> Enum.map(& &1.line_no)
        |> Enum.sort()

      assert line_numbers == [5, 6, 7]
    end)
  end

  test "ignores sleeps outside test files" do
    """
    defmodule Example.Worker do
      def run do
        Process.sleep(10)
        :timer.sleep(10)
      end
    end
    """
    |> to_source_file("lib/example/worker.ex")
    |> run_check(NoSleepInTests)
    |> refute_issues()
  end

  test "ignores other Process and :timer functions" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        Process.send_after(self(), :tick, :timer.seconds(1))
        assert_receive :tick, :timer.seconds(2)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSleepInTests)
    |> refute_issues()
  end
end
