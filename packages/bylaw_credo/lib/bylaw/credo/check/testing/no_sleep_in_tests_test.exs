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
                 "Wait on a fact, never on time: wait on a message with `assert_receive`, " <>
                 "or pass the time in explicitly instead of waiting for the clock."
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

  test "reports a receive that only has an after clause, with its line" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        receive do
        after
          50 -> :ok
        end

        receive do after 10 -> :ok end
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSleepInTests)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {5, "receive after"},
               {10, "receive after"}
             ]
    end)
  end

  test "allows a receive that waits for a message, with or without a timeout" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        receive do
          :done -> :ok
        after
          1_000 -> flunk("no message")
        end

        receive do
          :done -> :ok
        end
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSleepInTests)
    |> refute_issues()
  end

  test "allows sleeping forever to keep a process alive" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "does something" do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        other = spawn(fn -> receive do after :infinity -> :ok end end)
        assert Process.alive?(pid) and Process.alive?(other)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSleepInTests)
    |> refute_issues()
  end

  test "reports sleeps called through an alias" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true
      alias Process, as: P

      test "does something" do
        P.sleep(10)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSleepInTests)
    |> assert_issue(fn issue -> assert issue.trigger == "Process.sleep" end)
  end

  test "reports sleeps in test support files" do
    """
    defmodule MyApp.Eventually do
      def wait(fun) do
        if fun.(), do: :ok, else: (Process.sleep(5); wait(fun))
      end
    end
    """
    |> to_source_file("test/support/eventually.ex")
    |> run_check(NoSleepInTests)
    |> assert_issue(fn issue -> assert issue.line_no == 3 end)
  end

  test "skips files matching :excluded_paths" do
    """
    defmodule MyApp.SlowServer do
      def answer, do: Process.sleep(100)
    end
    """
    |> to_source_file("test/support/slow_server.ex")
    |> run_check(NoSleepInTests, excluded_paths: ["test/support/slow_server.ex"])
    |> refute_issues()
  end

  test "checks only the files in :included_paths" do
    """
    defmodule MyApp.Worker do
      def run, do: Process.sleep(100)
    end
    """
    |> to_source_file("test/helpers/worker.ex")
    |> run_check(NoSleepInTests, included_paths: ["test/helpers/"])
    |> assert_issue()
  end
end
