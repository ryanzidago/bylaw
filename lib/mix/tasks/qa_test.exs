defmodule Mix.Tasks.QaTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Qa

  describe "prep_stage/0" do
    test "returns the ordered preparation command plan" do
      assert Qa.prep_stage() == %{
               label: "prep",
               commands: [
                 ["deps.unlock", "--unused"],
                 ["format"],
                 ["compile", "--warnings-as-errors"],
                 ["hex.audit"],
                 ["deps.audit"],
                 ["sobelow", "--strict", "--quiet", "--exit"]
               ]
             }
    end
  end

  describe "parallel_stages/1" do
    test "returns the non-coverage command plan" do
      stages = Qa.parallel_stages(%{coverage: false, failures_only: false})

      assert Enum.map(stages, & &1.label) == ["credo", "dialyzer", "test"]

      assert Enum.map(stages, & &1.commands) == [
               [["credo", "suggest", "--strict", "--verbose"]],
               [["dialyzer", "--no-compile", "--quiet-with-result"]],
               [["test", "--no-compile"]]
             ]
    end

    test "uses the coverage test command when coverage is enabled" do
      stages = Qa.parallel_stages(%{coverage: true, failures_only: false})

      assert List.last(stages).commands == [["test", "--cover", "--no-compile"]]
    end
  end

  describe "parse_args!/1" do
    test "parses supported switches" do
      assert Qa.parse_args!(["--coverage", "--failures-only"]) == %{
               coverage: true,
               failures_only: true
             }
    end

    test "defaults switches to false" do
      assert Qa.parse_args!([]) == %{
               coverage: false,
               failures_only: false
             }
    end

    test "rejects positional arguments" do
      assert_raise Mix.Error, "mix qa does not accept positional arguments: unexpected", fn ->
        Qa.parse_args!(["unexpected"])
      end
    end
  end

  describe "extract_coverage_rows/1" do
    test "extracts coverage rows and strips ANSI escapes" do
      results = [
        %{
          exit_code: 0,
          output: "\e[32m| 95.00% | Bylaw.Covered |\e[0m\n| 80.25% | Bylaw.Low |\n",
          stage: "test"
        }
      ]

      assert Qa.extract_coverage_rows(results) == [
               {9500, "Bylaw.Covered"},
               {8025, "Bylaw.Low"}
             ]
    end
  end

  describe "filtered_coverage_rows/2" do
    test "keeps low module rows and always keeps the total row" do
      rows = [
        {9500, "Bylaw.Covered"},
        {8025, "Bylaw.Low"},
        {9100, "Total"}
      ]

      assert Qa.filtered_coverage_rows(rows, 9000) == [
               {8025, "Bylaw.Low"},
               {9100, "Total"}
             ]
    end
  end
end
