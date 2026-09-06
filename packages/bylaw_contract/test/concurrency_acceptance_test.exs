defmodule Bylaw.Contract.ConcurrencyAcceptanceTest do
  use ExUnit.Case, async: false

  setup %{tmp_dir: directory} do
    on_exit(fn -> File.rm_rf!(directory) end)
    :ok
  end

  @tag :tmp_dir
  test "native runner independently applies compilation and execution concurrency", context do
    output =
      run(context, "independent", ["--max-requires", "1", "--max-cases", "4", "--diagnostic"])

    [row] = read(output, "results.json")
    assert row["result"]["concurrency"]["max_cases"] == 4
    spans = read(output, "1-defaults-spans.json")
    require_span = Enum.find(spans, &(&1["function"] == "{\"Mix.Compilers.Test\", :require, 2}"))
    assert require_span["details"]["max_requires"] == 1
    assert require_span["details"]["test_file_count"] == 12
  end

  @tag :tmp_dir
  test "explicit concurrency settings preserve the complete fixture workload and observations",
       context do
    one = run(context, "serial", ["--max-requires", "1", "--max-cases", "1"])
    many = run(context, "parallel", ["--max-requires", "4", "--max-cases", "4"])
    [first] = read(one, "results.json")
    [second] = read(many, "results.json")
    assert first["result"]["coverage_status"] == "complete"
    assert second["result"]["coverage_status"] == "complete"
    assert first["result"]["coverage_sha256"] == second["result"]["coverage_sha256"]

    for output <- [one, many] do
      {_, status} =
        System.cmd(
          "elixir",
          ["qa/verify-performance-fixture.exs", Path.join(output, "1-defaults.etf")],
          stderr_to_stdout: true
        )

      assert status == 0
    end
  end

  @tag :tmp_dir
  test "native defaults retain effective concurrency and asynchronous case counts", context do
    output = run(context, "native", ["--max-requires", "default", "--max-cases", "default"])
    [row] = read(output, "results.json")
    concurrency = row["result"]["concurrency"]
    assert concurrency["max_cases"] == 2 * concurrency["schedulers_online"]
    assert concurrency["case_tests"] == %{"async" => 12}
    refute "--max-requires" in row["command"]
    refute "--max-cases" in row["command"]
  end

  @tag :tmp_dir
  test "concurrency controls reject nonpositive limits before running a workload", context do
    for {option, value} <- [{"--max-requires", "0"}, {"--max-cases", "-1"}] do
      output = Path.join(context.tmp_dir, option)

      {log, status} =
        System.cmd("python3", command(output, [option, value]), stderr_to_stdout: true)

      assert status == 2
      assert log =~ "positive integer or default"
      refute File.exists?(output)
    end
  end

  defp run(context, name, options) do
    output = Path.join(context.tmp_dir, name)
    {log, status} = System.cmd("python3", command(output, options), stderr_to_stdout: true)
    assert status == 0, log
    output
  end

  defp command(output, options) do
    [
      "qa/run-performance-phases.py",
      "fixture",
      "qa/performance_phase_fixture",
      output,
      "--modes",
      "defaults",
      "--trials",
      "1"
    ] ++ options
  end

  defp read(output, name), do: output |> Path.join(name) |> File.read!() |> JSON.decode!()
end
