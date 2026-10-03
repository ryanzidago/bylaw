defmodule Bylaw.Contract.ReportAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.Fixtures.Greeter
  alias Bylaw.Contract.Fixtures.Opaque
  alias Bylaw.Contract.Fixtures.Plain
  alias Bylaw.Contract.Report

  test "prints nothing when no property is missed" do
    report = Contract.observe([Plain], fn -> Plain.single(1) end)

    assert Report.format(report, colors: false) == ""
  end

  test "prints location category source and the exact missed property for each finding" do
    report =
      Contract.observe([Greeter], fn ->
        Greeter.greet(:admin)
        Greeter.greet(:member)
      end)

    output = Report.format(report, colors: false)

    assert output =~ "Bylaw.Contract.Fixtures.Greeter.greet/1"
    assert output =~ "test/support/fixtures.ex:"
    assert output =~ "Untested clause"
    assert output =~ ~s|def greet({:guest, _id}), do: "guest"|
    assert output =~ "clause 3"
    assert output =~ "Untested argument alternative"
    assert output =~ "{:guest, non_neg_integer()}"
    assert output =~ "@spec greet(audience()) :: String.t()"
    refute output =~ "\e["
  end

  test "keeps unassessable properties in the data but out of the printed report" do
    report = Contract.observe([Opaque], fn -> Opaque.token(true) end)

    assert Enum.any?(report.properties, &(&1.status == :unassessable))
    refute Report.format(report, colors: false) =~ "unassessable"
    refute Report.format(report, colors: false) =~ "Untested return alternative"
  end

  test "summarises how many properties were observed missed and unassessable" do
    report = Contract.observe([Greeter], fn -> Greeter.greet(:admin) end)

    summary = Report.summary(report)

    assert summary.properties == summary.observed + summary.missed + summary.unassessable
    assert summary.missed > 0
    assert summary.observed > 0
  end

  test "ends the report by saying a gap means a missing test, a spec or guard wider than the code, or dead code" do
    report =
      Bylaw.Contract.observe([Bylaw.Contract.Fixtures.Greeter], fn ->
        Bylaw.Contract.Fixtures.Greeter.greet(:admin)
      end)

    output = Bylaw.Contract.Report.format(report, colors: false)

    assert output =~ "add a test, narrow the spec or guard, or delete the unreachable code"
  end
end
