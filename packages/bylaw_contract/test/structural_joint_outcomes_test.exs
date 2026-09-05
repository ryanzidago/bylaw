defmodule Bylaw.Contract.StructuralJointOutcomesTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.Check.FunctionClauses
  alias Bylaw.Contract.StructuralJointFixture, as: Fixture

  test "retains head matches when guarded map access fails" do
    verify(:map_value, %{payload: %{ok: true}}, :ok, [
      {1, 1, 0, 1},
      {1, 1, 0, 0},
      {1, 1, 0, 0},
      {1, 1, 0, 0}
    ])

    verify(:map_value, %{payload: %{}}, :map, [
      {1, 0, 1, 0},
      {1, 1, 0, 1},
      {1, 1, 0, 0},
      {1, 1, 0, 0}
    ])

    verify(:map_value, %{payload: 42}, :payload, [
      {1, 0, 1, 0},
      {1, 0, 1, 0},
      {1, 1, 0, 1},
      {1, 1, 0, 0}
    ])

    verify(:map_value, %{}, :other, [
      {0, 0, 0, 0},
      {0, 0, 0, 0},
      {0, 0, 0, 0},
      {1, 1, 0, 1}
    ])
  end

  test "preserves alternative guards when an earlier guard raises" do
    verify(:alternative, :atom, :accepted, [{1, 1, 0, 1}, {1, 1, 0, 0}])
    verify(:alternative, %{key: :value}, :accepted, [{1, 1, 0, 1}, {1, 1, 0, 0}])
    verify(:alternative, %{}, :other, [{1, 0, 1, 0}, {1, 1, 0, 1}])
    verify(:alternative, [], :other, [{1, 0, 1, 0}, {1, 1, 0, 1}])
  end

  test "preserves repeated-variable head matches independently of guards" do
    verify(:repeated, {1, 1}, :equal_integer, [{1, 1, 0, 1}, {1, 1, 0, 0}, {1, 1, 0, 0}])
    verify(:repeated, {1.0, 1.0}, :pair, [{1, 0, 1, 0}, {1, 1, 0, 1}, {1, 1, 0, 0}])
    verify(:repeated, {1, 1.0}, :pair, [{0, 0, 0, 0}, {1, 1, 0, 1}, {1, 1, 0, 0}])
    verify(:repeated, :atom, :other, [{0, 0, 0, 0}, {0, 0, 0, 0}, {1, 1, 0, 1}])
  end

  test "preserves dependent binary sizes and guard rejection outcomes" do
    verify(:bytes, <<1, 7>>, :nonempty, [{1, 1, 0, 1}, {1, 1, 0, 0}, {1, 1, 0, 0}])
    verify(:bytes, <<0>>, :other_binary, [{1, 0, 1, 0}, {1, 1, 0, 1}, {1, 1, 0, 0}])
    verify(:bytes, <<2, 7>>, :other_binary, [{0, 0, 0, 0}, {1, 1, 0, 1}, {1, 1, 0, 0}])
    verify(:bytes, <<>>, :other, [{0, 0, 0, 0}, {0, 0, 0, 0}, {1, 1, 0, 1}])
  end

  defp verify(function, argument, expected_result, expected_outcomes) do
    {:ok, tracer} = Contract.start([Fixture], checks: [FunctionClauses])

    try do
      assert apply(Fixture, function, [argument]) == expected_result
      coverage = Contract.stop(tracer)
      refute Map.has_key?(coverage, :incomplete)
      assert coverage.arity_calls[{Fixture, function, 1}] == 1

      actual =
        coverage.clauses
        |> Enum.filter(&(&1.module == Fixture and &1.function == function and &1.arity == 1))
        |> Enum.sort_by(& &1.position)
        |> Enum.map(fn clause ->
          outcome = Map.fetch!(coverage.clause_outcomes, clause.id)
          {outcome.head_matches, outcome.guard_passes, outcome.guard_rejections, outcome.selected}
        end)

      assert actual == expected_outcomes
    after
      if Process.alive?(tracer), do: Contract.stop(tracer)
    end
  end
end
