defmodule Bylaw.Contract.WarmSessionAcceptanceTest do
  use ExUnit.Case, async: true, group: :contract_qa_fixture

  @tag :tmp_dir
  test "repeated loaded ExUnit runs preserve exact observations and reclaim owned resources",
       context do
    {result, 0} = run(context, "complete,complete,complete")
    assert Enum.map(result["sessions"], & &1["test_result"]["total"]) == [12, 12, 12]
    assert length(Enum.uniq(Enum.map(result["sessions"], & &1["os_pid"]))) == 1
    assert length(Enum.uniq(Enum.map(result["sessions"], & &1["observer"]))) == 3
    assert Enum.all?(result["sessions"], & &1["cleanup"]["all_released"])
    assert length(Enum.uniq(Enum.map(result["sessions"], & &1["coverage_sha256"]))) == 1
    assert length(Enum.uniq(Enum.map(result["sessions"], & &1["report_sha256"]))) == 1
    assert Enum.all?(result["sessions"], &(&1["exact_fixture_counts"] == true))
  end

  @tag :tmp_dir
  test "a failed test followed by a successful run keeps both results and fresh observations",
       context do
    {result, 2} = run(context, "complete,failure,complete")
    assert Enum.map(result["sessions"], & &1["test_result"]["failures"]) == [0, 1, 0]
    assert Enum.all?(result["sessions"], & &1["cleanup"]["all_released"])
    assert Enum.all?(result["sessions"], &(&1["exact_fixture_counts"] == true))
  end

  @tag :tmp_dir
  test "incomplete observation followed by a successful run clears stale observer state",
       context do
    {result, 2} = run(context, "complete,overflow,complete")

    assert Enum.map(result["sessions"], & &1["coverage_status"]) == [
             "complete",
             "incomplete",
             "complete"
           ]

    [first, _, last] = result["sessions"]
    assert first["coverage_sha256"] == last["coverage_sha256"]
    assert last["exact_fixture_counts"]
    assert Enum.all?(result["sessions"], & &1["cleanup"]["all_released"])
  end

  @tag :tmp_dir
  test "warm run aggregation preserves failure and incomplete outcomes after later success",
       context do
    {result, 2} = run(context, "failure,overflow,complete")
    assert result["aggregate_exit_code"] == 2
    assert result["sessions"] |> List.last() |> get_in(["test_result", "failures"]) == 0
    assert length(result["sessions"]) == 3
  end

  defp run(context, scenarios) do
    output = Path.join(context.tmp_dir, "evidence")
    on_exit(fn -> File.rm_rf!(context.tmp_dir) end)

    {_log, status} =
      System.cmd("python3", ["qa/run-warm-lifecycle.py", output, "--scenarios", scenarios],
        stderr_to_stdout: true
      )

    {output |> Path.join("sessions.json") |> File.read!() |> JSON.decode!(), status}
  end
end
