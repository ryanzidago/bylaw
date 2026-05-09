defmodule Bylaw.Db.IssueTest do
  use ExUnit.Case, async: true

  doctest Bylaw.Db.Issue

  alias Bylaw.Db.Issue

  describe "format/1" do
    test "formats an issue without metadata" do
      issue = %Issue{check: SampleCheck, message: "database failed"}

      assert Issue.format(issue) == "#{inspect(SampleCheck)}: database failed"
    end

    test "omits metadata by default" do
      issue = %Issue{
        check: SampleCheck,
        message: "database failed",
        meta: %{schema: "public", table: "orders"}
      }

      assert Issue.format(issue) == "#{inspect(SampleCheck)}: database failed"
    end

    test "formats an issue with metadata when requested" do
      issue = %Issue{
        check: SampleCheck,
        message: "database failed",
        meta: %{schema: "public", table: "orders"}
      }

      assert Issue.format(issue, meta: true) ==
               "#{inspect(SampleCheck)}: database failed #{inspect(issue.meta)}"
    end

    test "omits empty metadata when requested" do
      issue = %Issue{check: SampleCheck, message: "database failed"}

      assert Issue.format(issue, meta: true) == "#{inspect(SampleCheck)}: database failed"
    end
  end

  describe "format_many/1" do
    test "formats an empty issue list" do
      assert Issue.format_many([]) == ""
    end

    test "joins formatted issues with newlines" do
      issues = [
        %Issue{check: FirstCheck, message: "first"},
        %Issue{check: SecondCheck, message: "second"}
      ]

      assert Issue.format_many(issues) ==
               "#{inspect(FirstCheck)}: first\n#{inspect(SecondCheck)}: second"
    end

    test "omits metadata by default" do
      issues = [
        %Issue{check: FirstCheck, message: "first", meta: %{table: "orders"}},
        %Issue{check: SecondCheck, message: "second", meta: %{table: "line_items"}}
      ]

      assert Issue.format_many(issues) ==
               "#{inspect(FirstCheck)}: first\n#{inspect(SecondCheck)}: second"
    end

    test "passes format options to each issue" do
      issues = [
        %Issue{check: FirstCheck, message: "first", meta: %{table: "orders"}},
        %Issue{check: SecondCheck, message: "second", meta: %{table: "line_items"}}
      ]

      assert Issue.format_many(issues, meta: true) ==
               "#{inspect(FirstCheck)}: first #{inspect(%{table: "orders"})}\n#{inspect(SecondCheck)}: second #{inspect(%{table: "line_items"})}"
    end
  end
end
