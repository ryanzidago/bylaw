defmodule Bylaw.CheckRunnerTest do
  use ExUnit.Case, async: true

  alias Bylaw.CheckRunner

  defmodule Issue do
    defstruct [:message]
  end

  defmodule OtherIssue do
    defstruct [:message]
  end

  defmodule Check do
  end

  describe "result!/4" do
    test "returns no issues for :ok" do
      assert [] = CheckRunner.result!(Check, :ok, Issue, 3)
    end

    test "returns non-empty issue lists" do
      issues = [%Issue{message: "failed"}]

      assert ^issues = CheckRunner.result!(Check, {:error, issues}, Issue, 3)
    end

    test "raises for empty issue lists" do
      assert_raise ArgumentError,
                   "expected #{inspect(Check)}.validate/3 to return :ok or {:error, non_empty_issue_list}, got: {:error, []}",
                   fn ->
                     CheckRunner.result!(Check, {:error, []}, Issue, 3)
                   end
    end

    test "raises for issue structs from another family" do
      result = {:error, [%OtherIssue{message: "failed"}]}

      assert_raise ArgumentError,
                   "expected #{inspect(Check)}.validate/3 to return :ok or {:error, non_empty_issue_list}, got: #{inspect(result)}",
                   fn ->
                     CheckRunner.result!(Check, result, Issue, 3)
                   end
    end

    test "raises for malformed results" do
      assert_raise ArgumentError,
                   "expected #{inspect(Check)}.validate/2 to return :ok or {:error, non_empty_issue_list}, got: :error",
                   fn ->
                     CheckRunner.result!(Check, :error, Issue, 2)
                   end
    end
  end
end
