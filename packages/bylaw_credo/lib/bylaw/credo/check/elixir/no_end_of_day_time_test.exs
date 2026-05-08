defmodule Bylaw.Credo.Check.Elixir.NoEndOfDayTimeTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoEndOfDayTime

  test "reports ~T[23:59:59]" do
    """
    defmodule Example do
      def run do
        ~T[23:59:59]
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoEndOfDayTime)
    |> assert_issue()
  end

  test "does not report values in excluded test paths" do
    """
    defmodule ExampleTest do
      def run do
        ~T[23:59:59]
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoEndOfDayTime, excluded_paths: ["test/"])
    |> refute_issues()
  end

  test "does not report other times" do
    """
    defmodule Example do
      def run do
        ~T[00:00:00]
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoEndOfDayTime)
    |> refute_issues()
  end
end
