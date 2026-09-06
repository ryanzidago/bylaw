prototype_path = Path.expand("../qa/bounded-preparation.exs", __DIR__)
if File.exists?(prototype_path), do: Code.require_file(prototype_path)

defmodule Bylaw.Contract.BoundedPreparationProbeTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Bylaw.Contract
  alias Bylaw.Contract.CallerGuardFixture
  alias Bylaw.Contract.Check.FunctionClauses
  alias Bylaw.Contract.StructuralCoverage
  alias Bylaw.Contract.StructuralExample
  alias Bylaw.Contract.StructuralJointFixture
  alias Bylaw.Contract.TestFixtures.SelectionDefaults

  setup do
    {:ok, existing} = StructuralCoverage.start_shadow([])
    on_exit(fn -> StructuralCoverage.stop_shadow(existing) end)
    :ok
  end

  test "bounded units preserve exact targets counters source locations and reports" do
    candidate = prototype()

    modules = [
      StructuralJointFixture,
      CallerGuardFixture,
      SelectionDefaults,
      StructuralExample,
      BylawBoundedAbsent
    ]

    before = capture(modules, FunctionClauses, &workload/0)
    after_units = capture(modules, {candidate, unit_size: 2}, &workload/0)
    assert after_units == before
    assert render(after_units) == render(before)
    assert after_units.arity_calls[{SelectionDefaults, :defaulted, 1}] == 1
    assert after_units.arity_calls[{SelectionDefaults, :defaulted, 2}] == 2
    assert after_units.arity_calls[{CallerGuardFixture, :who, 1}] == 1
    assert Enum.any?(after_units.structural_modules, &(&1.module == BylawBoundedAbsent))

    assert Enum.all?(after_units.clauses, fn clause ->
             is_binary(clause.file) and clause.line > 0 and is_binary(clause.source)
           end)
  end

  test "bounded units keep all modules active with distinct concurrent caller identities" do
    candidate = prototype()
    existing = MapSet.new(shadows())
    modules = [CallerGuardFixture, SelectionDefaults]
    {:ok, baseline} = Contract.start(modules, checks: [FunctionClauses])
    on_exit(fn -> stop_if_alive(baseline) end)
    {:ok, bounded} = Contract.start(modules, checks: [{candidate, unit_size: 1}])
    on_exit(fn -> stop_if_alive(bounded) end)
    assert length(shadows()) == MapSet.size(existing) + 3
    parent = self()

    children =
      for _ <- 1..2 do
        spawn_link(fn ->
          result = {
            CallerGuardFixture.who(self()),
            CallerGuardFixture.who(parent),
            SelectionDefaults.defaulted(:value)
          }

          send(parent, {self(), result})
        end)
      end

    for child <- children, do: assert_receive({^child, {:caller, :other, {:brief, :value}}})
    first = Contract.stop(baseline) |> normalize()
    second = Contract.stop(bounded) |> normalize()
    assert first == second
    assert MapSet.new(shadows()) == existing
    refute Map.has_key?(second, :incomplete)
    assert second.arity_calls[{CallerGuardFixture, :who, 1}] == 4
    assert second.arity_calls[{SelectionDefaults, :defaulted, 1}] == 2

    [clause | _] = Enum.filter(second.clauses, &(&1.function == :who))

    assert second.clause_outcomes[clause.id] == %{
             head_matches: 4,
             guard_passes: 2,
             guard_rejections: 2,
             selected: 2
           }
  end

  test "bounded startup failure releases partial units and preserves existing shadows" do
    candidate = prototype()
    existing = MapSet.new(shadows())
    assert MapSet.size(existing) <= 31

    held =
      for _ <- List.duplicate(:slot, 31 - MapSet.size(existing)) do
        {:ok, shadow} = StructuralCoverage.start_shadow([])
        on_exit(fn -> StructuralCoverage.stop_shadow(shadow) end)
        shadow
      end

    occupied = MapSet.union(existing, MapSet.new(held))
    assert MapSet.size(occupied) == 31
    assert MapSet.new(shadows()) == occupied

    assert {:ok, aggregate, _} =
             FunctionClauses.init([CallerGuardFixture, SelectionDefaults], [], %{
               claims: MapSet.new()
             })

    FunctionClauses.terminate(aggregate)
    assert MapSet.new(shadows()) == occupied

    assert {:error, message} =
             apply(candidate, :init, [
               [CallerGuardFixture, SelectionDefaults],
               [unit_size: 1],
               %{claims: MapSet.new()}
             ])

    assert message == "all temporary structural classifier slots are in use"
    assert MapSet.new(shadows()) == occupied
  end

  test "bounded observers stop and restart without growing the shadow pool" do
    candidate = prototype()
    modules = [CallerGuardFixture, SelectionDefaults]
    initial_sessions = :trace.session_info(:all)
    existing = MapSet.new(shadows())

    for _ <- 1..5 do
      coverage =
        capture(modules, {candidate, unit_size: 1}, fn ->
          assert CallerGuardFixture.who(self()) == :caller
          assert SelectionDefaults.defaulted(:value) == {:brief, :value}
        end)

      assert coverage.arity_calls[{CallerGuardFixture, :who, 1}] == 1
      assert MapSet.new(shadows()) == existing
      assert :trace.session_info(:all) == initial_sessions
    end
  end

  defp prototype do
    assert Code.ensure_loaded?(BylawBoundedStructuralPreparation)
    BylawBoundedStructuralPreparation
  end

  defp capture(modules, check, fun) do
    {:ok, observer} = Contract.start(modules, checks: [check])

    try do
      fun.()
      coverage = Contract.stop(observer) |> normalize()
      refute Map.has_key?(coverage, :incomplete)
      coverage
    after
      stop_if_alive(observer)
    end
  end

  defp normalize(coverage) do
    update_in(coverage.checks, fn checks ->
      case Map.pop(checks, BylawBoundedStructuralPreparation) do
        {nil, checks} -> checks
        {data, checks} -> Map.put(checks, FunctionClauses, data)
      end
    end)
  end

  defp workload do
    assert CallerGuardFixture.who(self()) == :caller
    assert SelectionDefaults.defaulted(:value) == {:brief, :value}
    assert SelectionDefaults.defaulted(:value, :long) == {:long, :value}
    assert StructuralExample.classify(7) == :positive_integer
    assert StructuralExample.through_private(:private_exact) == :private_exact
    assert StructuralJointFixture.map_value(%{payload: :invalid}) == :payload
    assert StructuralJointFixture.repeated({1, 1.0}) == :pair
    assert StructuralJointFixture.bytes(<<1, 42>>) == :nonempty
  end

  defp render(coverage),
    do: capture_io(fn -> Bylaw.Contract.Report.print(coverage, :stdio, false) end)

  defp stop_if_alive(observer) do
    if Process.alive?(observer), do: Contract.stop(observer)
  end

  defp shadows do
    for {module, _} <- :code.all_loaded(),
        String.starts_with?(
          Atom.to_string(module),
          "Elixir.Bylaw.Contract.StructuralCoverage.Shadow"
        ),
        do: module
  end
end
