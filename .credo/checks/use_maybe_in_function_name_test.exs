defmodule Bylaw.Credo.Check.Readability.UseMaybeInFunctionNameTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Readability.UseMaybeInFunctionName

  test "reports conditional function names that end with _if_needed" do
    """
    defmodule Example do
      def complete_run_if_needed(run), do: run
    end
    """
    |> to_source_file()
    |> run_check(UseMaybeInFunctionName)
    |> assert_issues(1)
    |> assert_issues_match([
      %{
        line_no: 2,
        trigger: "complete_run_if_needed",
        message: ~r/maybe_complete_run/
      }
    ])
  end

  test "reports private functions and preserves bang suffixes in the suggestion" do
    """
    defmodule Example do
      defp refresh_cache_if_needed!(cache), do: cache
    end
    """
    |> to_source_file()
    |> run_check(UseMaybeInFunctionName)
    |> assert_issues(1)
    |> assert_issues_match([
      %{
        line_no: 2,
        trigger: "refresh_cache_if_needed!",
        message: ~r/maybe_refresh_cache!/
      }
    ])
  end

  test "reports guarded functions once per name and arity" do
    """
    defmodule Example do
      def complete_run_if_needed(run) when is_map(run), do: run
      def complete_run_if_needed(nil), do: nil
    end
    """
    |> to_source_file()
    |> run_check(UseMaybeInFunctionName)
    |> assert_issues(1)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.trigger == "complete_run_if_needed"
      assert issue.message =~ "maybe_complete_run"
    end)
  end

  test "does not report functions that already use maybe_" do
    """
    defmodule Example do
      def maybe_complete_run(run), do: run
    end
    """
    |> to_source_file()
    |> run_check(UseMaybeInFunctionName)
    |> refute_issues()
  end

  test "does not report unrelated function names" do
    """
    defmodule Example do
      def complete_run_when_ready(run), do: run
    end
    """
    |> to_source_file()
    |> run_check(UseMaybeInFunctionName)
    |> refute_issues()
  end
end
