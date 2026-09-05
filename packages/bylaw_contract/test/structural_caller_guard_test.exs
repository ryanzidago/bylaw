defmodule Bylaw.Contract.StructuralCallerGuardTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.CallerGuardFixture, as: Fixture
  alias Bylaw.Contract.Check.FunctionClauses

  test "selects a self guard using the traced caller identity" do
    coverage = capture(fn _ -> assert Fixture.who(self()) == :caller end)
    assert outcomes(coverage, :who) == [{1, 1, 0, 1}, {1, 1, 0, 0}]
  end

  test "rejects a self guard when its argument is the consumer identity" do
    coverage =
      capture(fn observer ->
        [consumer] = :sys.get_state(observer).workers
        assert Fixture.who(consumer) == :other
      end)

    assert outcomes(coverage, :who) == [{1, 0, 1, 0}, {1, 1, 0, 1}]
  end

  test "keeps caller identities distinct across interleaved child processes" do
    coverage =
      capture(fn _ ->
        parent = self()

        children =
          for _ <- 1..2 do
            spawn_link(fn ->
              send(parent, {self(), Fixture.who(self()), Fixture.who(parent)})
            end)
          end

        for child <- children, do: assert_receive({^child, :caller, :other})
      end)

    assert coverage.arity_calls[{Fixture, :who, 1}] == 4
    assert outcomes(coverage, :who) == [{4, 2, 2, 2}, {4, 4, 0, 2}]
  end

  test "uses the caller identity inside nested and alternative guards" do
    coverage =
      capture(fn observer ->
        assert Fixture.nested(%{owner: self()}) == :caller
        assert Fixture.nested(self()) == :caller
        assert Fixture.nested(%{owner: observer}) == :other
      end)

    assert outcomes(coverage, :nested) == [{3, 2, 1, 2}, {3, 3, 0, 1}]
  end

  defp capture(fun) do
    {:ok, observer} = Contract.start([Fixture], checks: [FunctionClauses])

    try do
      fun.(observer)
      coverage = Contract.stop(observer)
      refute Map.has_key?(coverage, :incomplete)
      coverage
    after
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end

  defp outcomes(coverage, function) do
    coverage.clauses
    |> Enum.filter(&(&1.function == function))
    |> Enum.sort_by(& &1.position)
    |> Enum.map(fn clause ->
      counts = Map.fetch!(coverage.clause_outcomes, clause.id)
      {counts.head_matches, counts.guard_passes, counts.guard_rejections, counts.selected}
    end)
  end
end
