defmodule Bylaw.Contract.ProcessMetricsAcceptanceTest do
  use ExUnit.Case, async: false

  test "bounded QA commands run when optional native time is unavailable" do
    {output, status} =
      System.cmd(
        "python3",
        ["test/support/process_metrics.py", "ProcessMetricsTest.test_missing_native_time"],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end

  test "Linux resource counters use a compatible format and retain units" do
    {output, status} =
      System.cmd(
        "python3",
        ["test/support/process_metrics.py", "ProcessMetricsTest.test_linux_native_format"],
        stderr_to_stdout: true
      )

    assert status == 0, output
  end
end
