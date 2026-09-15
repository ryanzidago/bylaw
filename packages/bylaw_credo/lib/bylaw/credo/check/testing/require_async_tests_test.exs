defmodule Bylaw.Credo.Check.Testing.RequireAsyncTestsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.RequireAsyncTests

  test "reports async false without an explanatory comment" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> assert_issues(1)
    |> assert_issues_match([
      %{line_no: 2, trigger: "async: false", message: ~r/async: true/}
    ])
  end

  test "reports a missing async option" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> assert_issues(1)
    |> assert_issues_match([
      %{line_no: 2, trigger: "use ExUnit.Case", message: ~r/async: true/}
    ])
  end

  test "does not report async true" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: true

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> refute_issues()
  end

  test "does not report async false with an explanatory comment directly above" do
    """
    defmodule ExampleTest do
      # async: false because these tests share the global application environment
      use ExUnit.Case, async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> refute_issues()
  end

  test "does not report async false with a multi-line comment block above" do
    """
    defmodule ExampleTest do
      # async: false because these tests:
      # - share the global application environment
      # - depend on a single sandbox connection
      use ExUnit.Case, async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> refute_issues()
  end

  test "reports async false when a blank line separates the comment from the use" do
    """
    defmodule ExampleTest do
      # async: false because these tests share state

      use ExUnit.Case, async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> assert_issues(1)
  end

  test "reports a missing async option for ExUnit.CaseTemplate" do
    """
    defmodule ExampleCase do
      use ExUnit.CaseTemplate

      using do
        quote do
          :ok
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> assert_issues(1)
  end

  test "does not report async true for ExUnit.CaseTemplate" do
    """
    defmodule ExampleCase do
      use ExUnit.CaseTemplate, async: true

      using do
        quote do
          :ok
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> refute_issues()
  end

  test "reports non-async app case modules configured via case_modules" do
    """
    defmodule ExampleTest do
      use MyApp.DataCase, async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests, case_modules: [MyApp.DataCase])
    |> assert_issues(1)
  end

  test "does not report unknown case modules without configuration" do
    """
    defmodule ExampleTest do
      use MyApp.DataCase, async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> refute_issues()
  end

  test "does not report async false with a comment for configured case modules" do
    """
    defmodule ExampleTest do
      # async: false because the SQL sandbox is shared
      use MyApp.DataCase, async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests, case_modules: [MyApp.DataCase])
    |> refute_issues()
  end

  test "does not report a non-literal async option" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: async?()

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> refute_issues()
  end

  test "reports async false when the options continue on the next line" do
    """
    defmodule ExampleTest do
      use ExUnit.Case,
        async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> assert_issues(1)
    |> assert_issues_match([%{line_no: 2}])
  end

  test "does not report async false with a comment above a multi-line use" do
    """
    defmodule ExampleTest do
      # async: false because these tests share the global application environment
      use ExUnit.Case,
        async: false

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> refute_issues()
  end

  test "does not report async false with a trailing comment on the use line" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: false # shared application environment

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> refute_issues()
  end

  test "reports async false with an empty trailing comment marker on the use line" do
    """
    defmodule ExampleTest do
      use ExUnit.Case, async: false #

      test "example" do
        assert true
      end
    end
    """
    |> to_source_file()
    |> run_check(RequireAsyncTests)
    |> assert_issues(1)
  end
end
