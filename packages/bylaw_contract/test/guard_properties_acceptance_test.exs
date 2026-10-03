defmodule Bylaw.Contract.GuardPropertiesAcceptanceTest do
  use ExUnit.Case

  import Bylaw.Contract.ContractHelper

  alias Bylaw.Contract
  alias Bylaw.Contract.Fixtures.Ages
  alias Bylaw.Contract.Fixtures.Fallthrough
  alias Bylaw.Contract.Fixtures.Heads
  alias Bylaw.Contract.Fixtures.Kinds

  test "reports a guard that never rejected a call" do
    report = Contract.observe([Kinds], fn -> Kinds.kind(5) end)

    assert missed(report, Kinds, :guard_rejection) == [{:kind, 1, 1}, {:kind, 1, 2}]
  end

  test "counts a guard as rejecting when a call matched its head but failed the guard" do
    report =
      Contract.observe([Kinds], fn ->
        Kinds.kind(5)
        Kinds.kind(-3)
        Kinds.kind(:atom)
      end)

    assert missed(report, Kinds, :guard_rejection) == []
    assert missed(report, Kinds, :clause) == []
    assert property(report, Kinds, :guard_rejection, {:kind, 1, 1}).count == 2
    assert property(report, Kinds, :guard_rejection, {:kind, 1, 2}).count == 1
  end

  test "has no guard property for the last clause because its rejection cannot be observed" do
    report = Contract.observe([Ages], fn -> Ages.bucket(5) end)

    assert missed(report, Ages, :guard_rejection) == [{:bucket, 1, 1}]
    assert property(report, Ages, :guard_rejection, {:bucket, 1, 2}) == nil
  end

  test "does not count a guard that was never evaluated because an earlier clause handled the call" do
    report = Contract.observe([Kinds], fn -> Kinds.kind(5) end)

    assert property(report, Kinds, :guard_rejection, {:kind, 1, 2}).count == 0
  end

  test "treats a guard that fails with an exception as rejecting" do
    report = Contract.observe([Heads], fn -> Heads.first([]) end)

    assert property(report, Heads, :guard_rejection, {:first, 1, 1}).count == 1
  end

  test "has no guard property when no later clause could accept a call the guard rejects" do
    report = Contract.observe([Fallthrough], fn -> Fallthrough.route(:failed, 1) end)

    assert missed(report, Fallthrough, :guard_rejection) == [{:route, 2, 3}]
  end
end
