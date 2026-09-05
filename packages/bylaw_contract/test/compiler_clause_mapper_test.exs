defmodule Bylaw.Contract.CompilerClauseMapperTest do
  use ExUnit.Case, async: true

  alias Bylaw.Contract.CompilerClauseMapper
  alias Module.Types.Descr

  test "does not subtract guarded heads when analyzing a later fallback" do
    left = {:atom, 0, :left}
    variable = {:var, 0, :value}
    rules = [rule(:left, 1), rule(:right, 2)]
    clauses = [clause(left), clause(variable)]
    assert [%{output_ids: left_ids}, %{output_ids: right_ids}] = map(clauses, rules)
    assert left_ids == MapSet.new([:left])
    assert right_ids == MapSet.new([:right])

    guarded = [{:clause, 0, [left], [[{:atom, 0, true}]], []}, clause(variable)]
    assert Enum.empty?(map(guarded, rules))
  end

  test "does not mistake a numeric literal for the whole integer domain" do
    clauses = [clause({:integer, 0, 1}), clause({:var, 0, :value})]
    rules = [rule(Descr.integer(), :number, 1), rule(:other, 2)]
    assert Enum.empty?(map(clauses, rules))
  end

  test "does not split one broad source clause into separate inferred clause counters" do
    assert Enum.empty?(map([clause({:var, 0, :value})], [rule(:left, 1), rule(:right, 2)]))
  end

  test "uses inferred domains rather than rule ordering or indexes" do
    clauses = [clause({:atom, 0, :left}), clause({:atom, 0, :right})]
    expected = map(clauses, [rule(:left, 1), rule(:right, 2)])
    assert map(clauses, [rule(:right, 91), rule(:left, 42)]) == expected
  end

  test "does not assess inferred alternatives with no mapped source clause" do
    assert Enum.empty?(map([clause({:atom, 0, :left})], [rule(:left, 1), rule(:right, 2)]))
  end

  defp clause(pattern), do: {:clause, 0, [pattern], [], []}

  defp map(clauses, rules),
    do: CompilerClauseMapper.map([{:function, 0, :choose, 1, clauses}], __MODULE__, rules)

  defp rule(atom, index), do: rule(Descr.atom([atom]), atom, index)

  defp rule(type, output, index) do
    %{
      module: __MODULE__,
      function: :choose,
      arity: 1,
      index: index,
      argument_domain: Descr.tuple([type]),
      output_ids: MapSet.new([output])
    }
  end
end
