defmodule Bylaw.Contract.CompilerSourceClauseMappingTest do
  use ExUnit.Case

  alias Bylaw.Contract.Check.ElixirCompiler
  alias Bylaw.Contract.TestFixtures.CompilerSourceClauseTarget, as: Target

  test "does not credit a normalized keep rule when the discard source clause returns done" do
    coverage = observe(fn -> assert Target.choose({:discard, []}) == {:done, [], []} end)
    assert_observed(coverage, :choose, "{:done, term(), term()}")
    assert_unobserved(coverage, :choose, "{:keep, term()}")
  end

  test "does not report an exercised keep return as missed after a different branch is observed" do
    coverage =
      observe(fn ->
        assert Target.choose({:done, 0, 0}) == {:done, 0, 0}
        assert Target.choose({:keep, []}) == {:keep, []}
      end)

    assert_observed(coverage, :choose, "{:done, term(), term()}")
    assert_observed(coverage, :choose, "{:keep, term()}")
    assert coverage.compiler_calls[{Target, :choose, 1}] == 2
  end

  test "maps repeated and reordered source clauses independently of normalized rule positions" do
    coverage =
      observe(fn ->
        for function <- [:choose, :reordered] do
          assert apply(Target, function, [{:keep, []}]) == {:keep, []}
          assert apply(Target, function, [{:discard, []}]) == {:done, [], []}
          assert apply(Target, function, [[]]) == {:done, [], []}
        end
      end)

    for function <- [:choose, :reordered] do
      assert_observed(coverage, function, "{:keep, term()}")
      assert_observed(coverage, function, "{:done, term(), term()}")
      assert coverage.compiler_calls[{Target, function, 1}] == 3
    end
  end

  test "keeps ambiguous guarded and overlapping mappings unassessable without fabricated hits" do
    coverage = observe(fn -> assert Target.ambiguous(1) == :positive end)

    alternatives =
      Enum.filter(coverage.compiler_return_alternatives, &(&1.function == :ambiguous))

    assert length(alternatives) == 2
    assert Enum.all?(alternatives, &MapSet.member?(coverage.unknown, &1.id))
    refute Enum.any?(alternatives, &Map.has_key?(coverage.hits, &1.id))
  end

  test "preserves independent assessable functions when another function cannot be mapped" do
    coverage =
      observe(fn ->
        assert Target.ambiguous(1) == :positive
        assert Target.independent(:left) == :left
      end)

    assert_observed(coverage, :independent, ":left")
    assert_unobserved(coverage, :independent, ":right")
  end

  test "restores original compiled code after observing normalized source clauses" do
    original = Target.module_info(:md5)

    observe(fn ->
      refute Target.module_info(:md5) == original
      assert Target.choose({:keep, []}) == {:keep, []}
    end)

    assert Target.module_info(:md5) == original
    assert Target.choose({:discard, []}) == {:done, [], []}
  end

  defp observe(function) do
    {:ok, tracer} = Bylaw.Contract.start([Target], checks: [ElixirCompiler])

    try do
      function.()
      Bylaw.Contract.stop(tracer)
    after
      if Process.alive?(tracer), do: Bylaw.Contract.stop(tracer)
    end
  end

  defp assert_observed(coverage, function, label) do
    target =
      Enum.find(
        coverage.compiler_return_alternatives,
        &(&1.function == function and &1.label == label)
      )

    assert target
    refute MapSet.member?(coverage.unknown, target.id)
    assert coverage.hits[target.id] == 1
  end

  defp assert_unobserved(coverage, function, label) do
    target =
      Enum.find(
        coverage.compiler_return_alternatives,
        &(&1.function == function and &1.label == label)
      )

    assert target
    refute MapSet.member?(coverage.unknown, target.id)
    refute Map.has_key?(coverage.hits, target.id)
  end
end
