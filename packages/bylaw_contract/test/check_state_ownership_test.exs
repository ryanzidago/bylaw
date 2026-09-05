defmodule Bylaw.Contract.CheckStateOwnershipTest do
  use ExUnit.Case

  alias Bylaw.Contract.Check
  alias Bylaw.Contract.StructuralExample

  defmodule SharedCheck do
    @behaviour Bylaw.Contract.Check

    @impl Bylaw.Contract.Check
    def init(_modules, opts, context) do
      notify = Keyword.fetch!(opts, :notify)
      shared = Enum.to_list(1..1000)
      targets = [%{id: :sample, data: shared}]
      state = %{notify: notify, input_classes: targets, copies: List.duplicate(shared, 20)}
      send(notify, {:initialized, self(), context.claims, :erts_debug.size(state)})

      {:ok, state,
       %{
         calls: MapSet.new(Keyword.get(opts, :calls, [])),
         returns: MapSet.new(),
         claims: MapSet.new([:sample]),
         process_scope: Keyword.get(opts, :process_scope, :all)
       }}
    end

    @impl Bylaw.Contract.Check
    def observe(_event, state), do: state

    @impl Bylaw.Contract.Check
    def coverage(state), do: Map.take(state, [:input_classes])

    @impl Bylaw.Contract.Check
    def terminate(state) do
      send(state.notify, {:terminated, self()})
      :ok
    end
  end

  defmodule FailingCheck do
    @behaviour Bylaw.Contract.Check

    @impl Bylaw.Contract.Check
    def init(_modules, opts, context) do
      send(Keyword.fetch!(opts, :notify), {:failed_init, context.claims})
      {:error, "requested failure"}
    end

    @impl Bylaw.Contract.Check
    def observe(_event, state), do: state

    @impl Bylaw.Contract.Check
    def coverage(_state), do: %{}

    @impl Bylaw.Contract.Check
    def terminate(_state), do: :ok
  end

  test "check initialization and termination run in the owning worker" do
    {:ok, tracer} = start_shared()
    [worker] = :sys.get_state(tracer).workers
    coverage = Bylaw.Contract.stop(tracer)

    assert_receive {:initialized, owner, _, _}
    assert owner == worker
    assert_receive {:terminated, ^worker}
    assert coverage.input_classes == [%{id: :sample, data: Enum.to_list(1..1000)}]
    refute Process.alive?(worker)
  end

  test "worker startup preserves sharing inside check state" do
    {:ok, tracer} = start_shared()
    [worker] = :sys.get_state(tracer).workers
    assert_receive {:initialized, _, _, initial_words}
    parent = self()

    :sys.replace_state(worker, fn state ->
      send(parent, {:worker_words, :erts_debug.size(state.runtime.state)})
      state
    end)

    Bylaw.Contract.stop(tracer)
    assert_receive {:worker_words, worker_words}
    assert worker_words <= initial_words * 2
  end

  test "stop preserves complete coverage while sharing standard and per-check fields" do
    {:ok, tracer} = start_shared()
    coverage = Bylaw.Contract.stop(tracer)
    expected = [%{id: :sample, data: Enum.to_list(1..1000)}]
    assert coverage.input_classes == expected
    assert coverage.checks == %{SharedCheck => %{input_classes: expected}}
    assert coverage.hits == %{}
    assert coverage.calls == %{}
    assert :erts_debug.size(coverage) * 3 < :erts_debug.flat_size(coverage) * 2
  end

  test "checks receive ordered claims and clean up when later initialization fails" do
    previous = Process.flag(:trap_exit, true)

    try do
      assert {:error, "requested failure"} =
               Bylaw.Contract.start([],
                 checks: [
                   {SharedCheck, notify: self()},
                   {FailingCheck, notify: self()}
                 ]
               )

      assert_receive {:initialized, owner, claims, _}
      assert claims == MapSet.new()
      assert_receive {:failed_init, later_claims}
      assert later_claims == MapSet.new([:sample])
      assert_receive {:terminated, ^owner}
      refute Process.alive?(owner)
    after
      Process.flag(:trap_exit, previous)
    end
  end

  test "structural workers release classifier AST after shadow compilation" do
    {:ok, tracer} = Bylaw.Contract.start([StructuralExample], checks: [Check.FunctionClauses])
    [worker] = :sys.get_state(tracer).workers
    state = :sys.get_state(worker).runtime.state
    StructuralExample.classify(:exact)
    coverage = Bylaw.Contract.stop(tracer)

    refute Map.has_key?(state, :classifiers)
    refute Enum.empty?(coverage.clauses)
    assert coverage.arity_calls[{StructuralExample, :classify, 1}] == 1
  end

  test "concurrent observers keep independently owned check state" do
    {:ok, first} = start_shared()
    {:ok, second} = start_shared()
    [first_worker] = :sys.get_state(first).workers
    [second_worker] = :sys.get_state(second).workers
    assert first_worker != second_worker
    first_coverage = Bylaw.Contract.stop(first)
    assert Process.alive?(second_worker)
    second_coverage = Bylaw.Contract.stop(second)
    assert first_coverage == second_coverage
  end

  test "typespec indexes retain target data once" do
    {:ok, state, _} =
      Check.Typespec.init([Bylaw.Contract.Example.Registration], [], %{claims: MapSet.new()})

    coverage = Check.Typespec.coverage(state)
    assert :erts_debug.flat_size(state) < :erts_debug.flat_size(coverage) * 1.5
  end

  test "activation failure terminates initialized checks" do
    previous = Process.flag(:trap_exit, true)

    try do
      assert {:error, reason} =
               Bylaw.Contract.start([],
                 checks: [
                   {SharedCheck,
                    notify: self(),
                    calls: [{StructuralExample, :classify, 1}],
                    process_scope: :invalid_scope}
                 ]
               )

      assert reason =~ "could not configure"
      assert_receive {:initialized, owner, _, _}
      assert_receive {:terminated, ^owner}
      refute Process.alive?(owner)
    after
      Process.flag(:trap_exit, previous)
    end
  end

  test "an abnormal worker exit terminates sibling checks" do
    previous = Process.flag(:trap_exit, true)

    try do
      {:ok, tracer} =
        Bylaw.Contract.start([StructuralExample],
          checks: [
            Check.FunctionClauses,
            {SharedCheck, notify: self()}
          ]
        )

      [first, sibling] = :sys.get_state(tracer).workers
      monitor = Process.monitor(tracer)
      Process.exit(first, :kill)
      assert_receive {:terminated, ^sibling}
      assert_receive {:DOWN, ^monitor, :process, ^tracer, :killed}
      refute Process.alive?(sibling)
    after
      Process.flag(:trap_exit, previous)
    end
  end

  test "compiler observation does not hot-reload its active runtime modules" do
    {:ok, state, _} =
      Check.ElixirCompiler.init([Bylaw.Contract.Tracer], [], %{claims: MapSet.new()})

    instrumented = Map.keys(state.instrumented_modules)
    coverage = Check.ElixirCompiler.coverage(state)
    Check.ElixirCompiler.terminate(state)

    assert Enum.empty?(instrumented)
    assert Enum.any?(coverage.compiler_warnings, &String.contains?(&1, "observer runtime"))

    assert Enum.all?(
             coverage.compiler_return_alternatives,
             &MapSet.member?(coverage.unknown, &1.id)
           )
  end

  defp start_shared, do: Bylaw.Contract.start([], checks: [{SharedCheck, notify: self()}])
end
