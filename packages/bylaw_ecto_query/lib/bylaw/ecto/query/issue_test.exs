defmodule Bylaw.Ecto.Query.IssueTest do
  use ExUnit.Case, async: true

  alias Bylaw.Ecto.Query.Issue

  describe "format/1" do
    test "formats an issue without metadata" do
      issue = %Issue{check: SampleCheck, message: "query failed"}

      assert Issue.format(issue) == "#{inspect(SampleCheck)}: query failed"
    end

    test "omits metadata by default" do
      issue = %Issue{check: SampleCheck, message: "query failed", meta: %{operation: :all}}

      assert Issue.format(issue) == "#{inspect(SampleCheck)}: query failed"
    end

    test "formats an issue with metadata when requested" do
      issue = %Issue{check: SampleCheck, message: "query failed", meta: %{operation: :all}}

      assert Issue.format(issue, meta: true) ==
               "#{inspect(SampleCheck)}: query failed %{operation: :all}"
    end

    test "omits empty metadata when requested" do
      issue = %Issue{check: SampleCheck, message: "query failed"}

      assert Issue.format(issue, meta: true) == "#{inspect(SampleCheck)}: query failed"
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
        %Issue{check: FirstCheck, message: "first", meta: %{operation: :all}},
        %Issue{check: SecondCheck, message: "second", meta: %{operation: :stream}}
      ]

      assert Issue.format_many(issues) ==
               "#{inspect(FirstCheck)}: first\n#{inspect(SecondCheck)}: second"
    end

    test "passes format options to each issue" do
      issues = [
        %Issue{check: FirstCheck, message: "first", meta: %{operation: :all}},
        %Issue{check: SecondCheck, message: "second", meta: %{operation: :stream}}
      ]

      assert Issue.format_many(issues, meta: true) ==
               "#{inspect(FirstCheck)}: first %{operation: :all}\n#{inspect(SecondCheck)}: second %{operation: :stream}"
    end
  end
end
