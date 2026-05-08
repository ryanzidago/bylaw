defmodule Bylaw.Credo.Check.Testing.NoTestsInTestDirTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.NoTestsInTestDir

  test "reports tests in test/" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "works" do
        assert true
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoTestsInTestDir)
    |> assert_issue()
  end

  test "does not report non-test files" do
    """
    defmodule Example do
      def run, do: :ok
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoTestsInTestDir)
    |> refute_issues()
  end
end
