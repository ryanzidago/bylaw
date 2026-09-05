defmodule Bylaw.Contract.IncompleteReportColorsTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  test "incomplete observations stay plain and do not become coverage gaps when colors are forced" do
    coverage = %{
      status: :incomplete,
      incomplete: [%{check: Bylaw.Contract.Check.Typespec, limit: 4096, observed: 4097}]
    }

    expected =
      "Bylaw.Contract observation incomplete; coverage gaps were not assessed.\n" <>
        "Bylaw.Contract.Check.Typespec: trace queue exceeded 4096 messages (observed 4097).\n"

    for enabled <- [false, true] do
      output =
        capture_io(fn -> Bylaw.Contract.print_report(coverage, :stdio, colors: enabled) end)

      assert output == expected
      refute output =~ "\e["
      refute output =~ "Missed"
    end
  end
end
