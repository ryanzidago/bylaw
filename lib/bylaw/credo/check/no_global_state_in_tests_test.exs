defmodule Bylaw.Credo.Check.NoGlobalStateInTestsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.NoGlobalStateInTests

  describe "Application" do
    test "reports Application.put_env" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          Application.put_env(:my_app, :key, :value)
          assert true
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Application.put_env"
      end)
    end

    test "reports Application.delete_env" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          Application.delete_env(:my_app, :key)
          assert true
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Application.delete_env"
      end)
    end

    test "reports Application.get_env" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          Application.get_env(:my_app, :key)
          assert true
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Application.get_env"
      end)
    end

    test "reports Application.fetch_env" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          Application.fetch_env(:my_app, :key)
          assert true
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Application.fetch_env"
      end)
    end

    test "reports Application.fetch_env!" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          Application.fetch_env!(:my_app, :key)
          assert true
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "Application.fetch_env!"
      end)
    end

    test "reports multiple Application calls" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          Application.put_env(:my_app, :key, :value)
          assert true
        after
          Application.delete_env(:my_app, :key)
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issues(fn issues ->
        assert Enum.count(issues) == 2
      end)
    end
  end

  describe "System" do
    test "reports System.put_env" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          System.put_env("KEY", "value")
          assert true
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "System.put_env"
      end)
    end

    test "reports System.delete_env" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          System.delete_env("KEY")
          assert true
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "System.delete_env"
      end)
    end

    test "reports System.get_env" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          System.get_env("KEY")
          assert true
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> assert_issue(fn issue ->
        assert issue.trigger == "System.get_env"
      end)
    end
  end

  describe "excluded paths" do
    test "respects excluded paths" do
      """
      defmodule SupportHelperTest do
        use ExUnit.Case

        test "configures" do
          Application.put_env(:my_app, :key, :value)
        end
      end
      """
      |> to_source_file("test/support/helper_test.exs")
      |> run_check(NoGlobalStateInTests, excluded_paths: ["test/support/"])
      |> refute_issues()
    end
  end

  describe "non-test files" do
    test "ignores Application calls in non-test files" do
      """
      defmodule MyApp.Config do
        def get_key do
          Application.get_env(:my_app, :key)
        end
      end
      """
      |> to_source_file("lib/my_app/config.ex")
      |> run_check(NoGlobalStateInTests)
      |> refute_issues()
    end

    test "ignores System calls in non-test files" do
      """
      defmodule MyApp.Config do
        def get_key do
          System.get_env("KEY")
        end
      end
      """
      |> to_source_file("lib/my_app/config.ex")
      |> run_check(NoGlobalStateInTests)
      |> refute_issues()
    end
  end

  describe "clean code" do
    test "does not report when no global state calls are present" do
      """
      defmodule ExampleTest do
        use ExUnit.Case, async: true

        test "does something" do
          assert 1 + 1 == 2
        end
      end
      """
      |> to_source_file("lib/example_test.exs")
      |> run_check(NoGlobalStateInTests)
      |> refute_issues()
    end
  end
end
