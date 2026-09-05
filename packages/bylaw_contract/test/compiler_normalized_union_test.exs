defmodule Bylaw.Contract.CompilerNormalizedUnionTest do
  use ExUnit.Case

  alias Bylaw.Contract.Check.ElixirCompiler
  alias Bylaw.Contract.CompilerInference
  alias Bylaw.Contract.CompilerInference.Elixir120
  alias Bylaw.Contract.TestFixtures.CompilerNormalizedUnionTarget
  alias Module.Types.Descr

  test "decodes a return union that absorbs a clause literal" do
    {:ok, decoded} = decode_returns([Descr.atom([:ok]), Descr.atom(), Descr.integer()])

    assert Enum.map(decoded.return_alternatives, & &1.label) == ["atom()", "integer()"]
    refute Enum.any?(decoded.return_alternatives, & &1.inferable?)
    assert Enum.empty?(decoded.inference_rules)
  end

  test "decodes a return union that merges tagged tuple fields" do
    {:ok, decoded} =
      decode_returns([
        Descr.tuple([Descr.atom([:ok]), Descr.atom([:one])]),
        Descr.tuple([Descr.atom([:ok]), Descr.atom([:two])]),
        Descr.atom([:error])
      ])

    assert length(decoded.return_alternatives) == 2
    assert Enum.all?(decoded.return_alternatives, & &1.supported?)
    assert Enum.all?(decoded.return_alternatives, & &1.runtime_safe?)
    refute Enum.any?(decoded.return_alternatives, & &1.inferable?)
    assert Enum.empty?(decoded.inference_rules)
  end

  test "decodes dynamic return alternatives without requiring identical clause labels" do
    {:ok, decoded} = decode_returns([Descr.dynamic(Descr.atom([:ok])), Descr.atom([nil])])

    assert length(decoded.return_alternatives) == 2
    refute Enum.any?(decoded.return_alternatives, & &1.inferable?)
    assert Enum.empty?(decoded.inference_rules)
  end

  test "preserves independent functions when a compiled module has normalized returns" do
    loaded = CompilerInference.load([CompilerNormalizedUnionTarget])
    assert [%{status: :supported}] = loaded.modules
    assert Enum.empty?(loaded.warnings)

    {:ok, tracer} =
      Bylaw.Contract.start([CompilerNormalizedUnionTarget], checks: [ElixirCompiler])

    assert CompilerNormalizedUnionTarget.independent(:left) == :left
    coverage = Bylaw.Contract.stop(tracer)

    independent =
      Enum.filter(coverage.compiler_return_alternatives, &(&1.function == :independent))

    assert length(independent) == 2
    assert Enum.all?(independent, & &1.inferable?)
    refute Enum.any?(independent, &MapSet.member?(coverage.unknown, &1.id))
    left = Enum.find(independent, &(&1.label == ":left"))
    right = Enum.find(independent, &(&1.label == ":right"))
    assert Map.fetch!(coverage.hits, left.id) == 1
    refute Map.has_key?(coverage.hits, right.id)
  end

  test "keeps functions without exact normalized clause mappings unassessable after a call" do
    {:ok, tracer} =
      Bylaw.Contract.start([CompilerNormalizedUnionTarget], checks: [ElixirCompiler])

    assert CompilerNormalizedUnionTarget.merged(:one) == {:ok, :one}
    coverage = Bylaw.Contract.stop(tracer)
    merged = Enum.filter(coverage.compiler_return_alternatives, &(&1.function == :merged))
    assert length(merged) == 2
    assert Enum.all?(merged, &MapSet.member?(coverage.unknown, &1.id))
    refute Enum.any?(merged, &Map.has_key?(coverage.hits, &1.id))
    assert Bylaw.Contract.summary(coverage).missed_compiler_return_alternatives == 0
  end

  defp decode_returns(returns) do
    clauses = Enum.map(returns, &{[Descr.term()], &1})
    exports = [{{:choose, 1}, %{sig: {:infer, nil, clauses}}}]
    Elixir120.return_alternatives(__MODULE__, exports)
  end
end
