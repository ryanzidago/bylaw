defmodule Bylaw.Contract.OwnershipProbeAcceptanceTest do
  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "ownership captures preserve the native parameterized inventory and immediate root callers",
       context do
    {result, 0} = run(context, "explicit", "immediate")
    assert length(result["tests"]) == 12
    assert Enum.all?(result["tests"], &(&1["state"] == "passed"))
    assert result["root_count"] == 12
    assert result["promised_expected_calls"] == 76
    assert result["promised_calls_exact"]
    assert result["caller_returns_exact"]
    assert result["registration"]["count"] == 12
    assert result["registration"]["peak"] == 4
    assert result["registration"]["retained"] == 0
    assert result["cleanup"]["clean"]
  end

  @tag :tmp_dir
  test "scoped comparisons preserve settled root calls and expose descendant and setup boundaries",
       context do
    for mode <- ["scan", "explicit", "all"] do
      {result, 0} = run(context, mode, "settled")
      assert result["oracle_calls"] == 124
      assert result["promised_calls_exact"]
      assert result["caller_returns_exact"]
      assert result["cleanup"]["clean"]

      if mode == "all" do
        assert result["all_calls_exact"]
      else
        for kind <- [
              "task",
              "nested_task",
              "supervised",
              "spawn",
              "preexisting",
              "setup_all",
              "on_exit"
            ] do
          assert result["observed_by_kind"][kind] == nil
        end
      end
    end
  end

  @tag :tmp_dir
  test "failed and timed out tests release explicit registrations workers and trace sessions",
       context do
    for scenario <- ["failure", "timeout"] do
      {result, 1} = run(context, "explicit", scenario)
      assert length(result["tests"]) == 12
      assert Enum.count(result["tests"], &(&1["state"] == "failed")) == 1
      assert result["registration"]["retained"] == 0
      assert result["cleanup"]["clean"]
    end
  end

  @tag :tmp_dir
  test "exhausted observation cannot be reactivated through explicit registration", context do
    {result, 0} = run(context, "explicit", "exhausted")
    assert result["incomplete"]
    assert result["rejected_after_exhaustion"]
    assert result["cleanup"]["clean"]
  end

  defp run(context, mode, scenario) do
    on_exit(fn -> File.rm_rf!(context.tmp_dir) end)
    output = Path.join(context.tmp_dir, mode <> "-" <> scenario <> ".json")

    {log, status} =
      System.cmd(
        "elixir",
        [
          "-pa",
          Application.app_dir(:bylaw_contract, "ebin"),
          "qa/ownership-probe.exs",
          mode,
          scenario,
          output,
          "0",
          "plain"
        ],
        stderr_to_stdout: true
      )

    assert File.regular?(output), log
    {output |> File.read!() |> JSON.decode!(), status}
  end
end
