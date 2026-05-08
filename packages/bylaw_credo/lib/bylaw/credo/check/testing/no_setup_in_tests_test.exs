defmodule Bylaw.Credo.Check.Testing.NoSetupInTestsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.NoSetupInTests

  test "reports setup blocks" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      setup do
        {:ok, user: :user}
      end

      test "works", %{user: user} do
        assert user
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSetupInTests)
    |> assert_issue()
  end

  test "reports setup_all blocks" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      setup_all do
        {:ok, user: :user}
      end

      test "works", %{user: user} do
        assert user
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoSetupInTests)
    |> assert_issue()
  end

  test "respects excluded paths" do
    """
    defmodule SupportCase do
      use ExUnit.Case

      setup do
        {:ok, conn: :conn}
      end
    end
    """
    |> to_source_file("test/support/conn_case.ex")
    |> run_check(NoSetupInTests, excluded_paths: ["test/support/"])
    |> refute_issues()
  end
end
