defmodule Bylaw.Contract.OverheadCaptureAcceptanceTest do
  use ExUnit.Case, async: true

  setup %{tmp_dir: directory} do
    on_exit(fn -> File.rm_rf!(directory) end)
    :ok
  end

  @tag :tmp_dir
  test "overhead summaries retain nil concurrent load timing and independent test times",
       context do
    result = capture("disabled", nil)
    {output, 0} = summarize(result, context.tmp_dir)
    summary = JSON.decode!(output)
    assert summary["ex_unit_timings"] == %{"async" => 90, "run" => 120, "load" => nil}
    assert summary["test_times_us"] == [40, 60]

    assert summary["compiler_options"] == %{
             "debug_info" => false,
             "docs" => false,
             "infer_signatures" => false
           }
  end

  @tag :tmp_dir
  test "overhead summaries distinguish combined defaults and preserve incomplete reasons",
       context do
    coverage = %{
      checks: %{Bylaw.Contract.Check.Typespec => %{}, Bylaw.Contract.Check.FunctionClauses => %{}},
      status: :incomplete,
      incomplete: [%{reason: :trace_queue_overflow, limit: 4096, observed: 5000}]
    }

    {output, 0} = summarize(capture("defaults", coverage), context.tmp_dir)
    summary = JSON.decode!(output)
    assert summary["coverage_status"] == "incomplete"
    assert summary["incomplete"] =~ "trace_queue_overflow"
    assert length(summary["checks"]) == 2
  end

  @tag :tmp_dir
  test "overhead summaries retain an exact deterministic coverage fingerprint", context do
    coverage = %{checks: %{Bylaw.Contract.Check.Typespec => %{counts: %{a: 2}}}}
    result = capture("typespec", coverage)
    {first, 0} = summarize(result, context.tmp_dir)
    changed = put_in(result.coverage.checks[Bylaw.Contract.Check.Typespec].counts.a, 3)
    {second, 0} = summarize(changed, context.tmp_dir)

    expected =
      coverage
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16()

    assert JSON.decode!(first)["coverage_sha256"] == expected
    refute JSON.decode!(second)["coverage_sha256"] == expected
  end

  @tag :tmp_dir
  test "overhead summaries reject a capture with the wrong check set", context do
    {_output, status} = summarize(capture("typespec", %{checks: %{}}), context.tmp_dir)
    refute status == 0
  end

  defp capture(mode, coverage) do
    %{
      mode: mode,
      coverage: coverage,
      elixir: System.version(),
      otp: System.otp_release(),
      options: [seed: 1, max_cases: 2],
      init_us: 10,
      observed_suite_us: 150,
      stop_us: 5,
      ex_unit_timings: %{async: 90, run: 120, load: nil},
      test_times_us: [40, 60],
      compiler_options: %{debug_info: false, docs: false, infer_signatures: false},
      test_states: %{passed: 2},
      failures: []
    }
  end

  defp summarize(result, directory) do
    input = Path.join(directory, "capture.etf")
    File.write!(input, :erlang.term_to_binary(result))
    System.cmd("elixir", ["qa/overhead-result.exs", input, result.mode], stderr_to_stdout: true)
  end
end
