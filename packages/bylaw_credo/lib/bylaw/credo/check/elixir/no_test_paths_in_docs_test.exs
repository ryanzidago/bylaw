defmodule Bylaw.Credo.Check.Elixir.NoTestPathsInDocsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoTestPathsInDocs

  test "reports a test path in @doc, @moduledoc and @typedoc" do
    """
    defmodule Sample do
      @moduledoc \"\"\"
      Memberships, as covered by test/functional/accounts_test.exs.
      \"\"\"

      @typedoc "See test/support/foo.ex."
      @type t :: %__MODULE__{user: term()}

      @doc "Answers :ok. Held to test/functional_web/api/membership_test.exs."
      def check(user), do: {:ok, user}
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoTestPathsInDocs)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {2, "test/functional/accounts_test.exs"},
               {6, "test/support/foo.ex"},
               {9, "test/functional_web/api/membership_test.exs"}
             ]

      assert hd(issues).message =~ "test path"
    end)
  end

  test "reports a heredoc doc with a path on its own line" do
    """
    defmodule Sample do
      @doc \"\"\"
      The behaviour of this module.

      Held to:
      test/functional/core/bulk_test.exs
      \"\"\"
      def check(user), do: {:ok, user}
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoTestPathsInDocs)
    |> assert_issue(fn issue ->
      assert issue.trigger == "test/functional/core/bulk_test.exs"
    end)
  end

  test "does not report paths that are not under test, or strings outside docs" do
    """
    defmodule Sample do
      @moduledoc "The module behind lib/functional/core/sample.ex."
      @doc "Answers :ok for a member, else {:error, :not_found}."

      def check(user), do: {:ok, user}

      def path, do: "test/functional/elsewhere_test.exs"
      def not_a_path(word), do: word =~ "contest/run"
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoTestPathsInDocs)
    |> refute_issues()
  end

  test "does not report a doc built from a variable or an interpolation" do
    ~S'''
    defmodule Sample do
      @doc doc_string()
      def a, do: :ok

      @doc "See #{path()}."
      def b, do: :ok

      defp doc_string, do: "See test/functional/x_test.exs."
      defp path, do: "test/functional/y_test.exs"
    end
    '''
    |> to_source_file("lib/sample.ex")
    |> run_check(NoTestPathsInDocs)
    |> refute_issues()
  end
end
