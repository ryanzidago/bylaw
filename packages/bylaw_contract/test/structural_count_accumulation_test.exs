defmodule Bylaw.Contract.StructuralCountAccumulationTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.Check.FunctionClauses
  alias Bylaw.Contract.StructuralJointFixture, as: Fixture

  test "accumulates selected and later clause outcomes across mixed calls" do
    coverage = observe(List.duplicate(inputs(), 5) |> List.flatten())
    assert coverage.arity_calls[{Fixture, :repeated, 1}] == 20

    outcomes =
      coverage.clauses
      |> Enum.filter(&(&1.function == :repeated))
      |> Enum.sort_by(& &1.position)
      |> Enum.map(fn clause ->
        counts = Map.fetch!(coverage.clause_outcomes, clause.id)
        {counts.head_matches, counts.guard_passes, counts.guard_rejections, counts.selected}
      end)

    assert outcomes == [{10, 5, 5, 5}, {15, 15, 0, 10}, {20, 20, 0, 5}]
    assert Enum.empty?(coverage.unmatched_clause_calls)
  end

  test "preserves exact coverage when call order changes" do
    values = List.duplicate(inputs(), 5) |> List.flatten()
    assert observe(values) == observe(Enum.reverse(values))
  end

  test "leaves uncalled functions without observed counters" do
    coverage = observe(inputs())
    refute Map.has_key?(coverage.arity_calls, {Fixture, :bytes, 1})

    coverage.clauses
    |> Enum.filter(&(&1.function == :bytes))
    |> Enum.each(fn clause -> refute Map.has_key?(coverage.clause_outcomes, clause.id) end)
  end

  defp inputs, do: [{1, 1}, {1.0, 1.0}, {1, 1.0}, :other]

  defp observe(values) do
    {:ok, tracer} = Contract.start([Fixture], checks: [FunctionClauses])

    try do
      Enum.each(values, &Fixture.repeated/1)
      coverage = Contract.stop(tracer)
      refute Map.has_key?(coverage, :incomplete)
      coverage
    after
      if Process.alive?(tracer), do: Contract.stop(tracer)
    end
  end
end
