defmodule Bylaw.Contract.TypePropertiesAcceptanceTest do
  use ExUnit.Case

  import Bylaw.Contract.ContractHelper

  alias Bylaw.Contract
  alias Bylaw.Contract.Fixtures.Ages
  alias Bylaw.Contract.Fixtures.Countdown
  alias Bylaw.Contract.Fixtures.Greeter
  alias Bylaw.Contract.Fixtures.Opaque
  alias Bylaw.Contract.Fixtures.Shapes

  test "reports a spec union member of an argument that no test passed" do
    report =
      Contract.observe([Greeter], fn ->
        Greeter.greet(:admin)
        Greeter.greet(:member)
      end)

    assert missed(report, Greeter, :argument_class) == ["{:guest, non_neg_integer()}"]
  end

  test "reports a range boundary of an argument that no test passed" do
    report =
      Contract.observe([Ages], fn ->
        Ages.bucket(17)
        Ages.bucket(18)
      end)

    assert missed(report, Ages, :argument_boundary) == ["0", "120"]
  end

  test "reports a return alternative that no test produced" do
    report = Contract.observe([Ages], fn -> Ages.bucket(17) end)

    assert missed(report, Ages, :return_alternative) == [":adult"]
  end

  test "reports nothing about types when every declared alternative was observed" do
    report =
      Contract.observe([Ages], fn ->
        for age <- [0, 17, 18, 120], do: Ages.bucket(age)
      end)

    assert missed(report, Ages, :argument_class) == []
    assert missed(report, Ages, :argument_boundary) == []
    assert missed(report, Ages, :return_alternative) == []
  end

  test "marks types it cannot assess as unassessable instead of missed" do
    report = Contract.observe([Opaque], fn -> Opaque.token(false) end)

    opaque =
      property(report, Opaque, :return_alternative, "token()")

    assert opaque.status == :unassessable
    assert missed(report, Opaque, :return_alternative) == [":ok"]
  end

  test "observes the arguments of a recursive function but not its returns" do
    report = Contract.observe([Countdown], fn -> Countdown.count_down(5) end)

    clauses = Enum.filter(report.properties, &(&1.module == Countdown and &1.kind == :clause))

    assert Enum.count(clauses) == 2
    assert Enum.all?(clauses, &(&1.status == :observed))
    assert property(report, Countdown, :return_alternative, ":done").status == :unassessable
    assert Enum.any?(report.warnings, &(&1 =~ "count_down/1" and &1 =~ "recursive"))
  end

  test "reports only declared alternatives, never value shapes it invents for a single declared type" do
    report = Contract.observe([Shapes], fn -> Shapes.describe("a", [1], 1, true) end)

    assert missed(report, Shapes, :argument_class) == ["false"]
  end
end
