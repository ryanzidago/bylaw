defmodule Bylaw.Contract.FunctionSelectionAcceptanceTest do
  use ExUnit.Case, async: false

  alias Bylaw.Contract
  alias Bylaw.Contract.Check
  alias Bylaw.Contract.Specs
  alias Bylaw.Contract.TypeMatcher
  alias Bylaw.Contract.TestFixtures.FunctionSelection, as: Fixture

  defmodule CustomCheck do
    @behaviour Bylaw.Contract.Check

    @impl Bylaw.Contract.Check
    def init(modules, opts, context) do
      send(Keyword.fetch!(opts, :notify), {:custom_initialized, modules, context})
      {:ok, %{}, %{calls: MapSet.new(), returns: MapSet.new(), claims: MapSet.new()}}
    end

    @impl Bylaw.Contract.Check
    def observe(_event, state), do: state

    @impl Bylaw.Contract.Check
    def coverage(_state), do: %{}

    @impl Bylaw.Contract.Check
    def terminate(_state), do: :ok
  end

  test "omitting function selection preserves full-scope observation" do
    {:ok, tracer} = Contract.start([Fixture])
    coverage = Contract.stop(tracer)
    assert MapSet.new(coverage.input_classes, & &1.function) == MapSet.new([:choose, :unrelated])
    assert MapSet.new(coverage.clauses, & &1.function) == MapSet.new([:choose, :unrelated])
  end

  test "typespec selection retains exact selected input boundary and return targets with child calls" do
    mfa = {Fixture, :choose, 1}
    baseline = Specs.load([Fixture])
    inputs = Enum.filter(baseline.input_classes ++ baseline.boundaries, &(&1.function == :choose))
    returns = Enum.filter(baseline.return_alternatives, &(&1.function == :choose))
    {:ok, tracer} = Contract.start([Fixture], checks: [Check.Typespec], only: [mfa])
    assert Fixture.choose(1) == :one
    task = Task.async(fn -> Fixture.choose(2) end)
    assert Task.await(task) == :other
    assert Fixture.unrelated(3) == :unused
    coverage = Contract.stop(tracer)

    assert MapSet.new(coverage.input_classes ++ coverage.boundaries, & &1.id) ==
             MapSet.new(inputs, & &1.id)

    assert MapSet.new(coverage.return_alternatives, & &1.id) == MapSet.new(returns, & &1.id)
    assert coverage.calls == %{mfa => 2}
    assert coverage.return_events == %{mfa => 2}

    for {targets, values} <- [{inputs, [1, 2]}, {returns, [:one, :other]}], target <- targets do
      expected = Enum.count(values, &(TypeMatcher.match(&1, target.match_type) == :match))
      assert Map.get(coverage.hits, target.id, 0) == expected
    end
  end

  test "structural selection retains only selected authored functions and callable arities" do
    mfa = {Fixture, :choose, 1}
    baseline = Bylaw.Contract.StructuralCoverage.load([Fixture])
    clauses = Enum.filter(baseline.clauses, &(&1.function == :choose))
    {:ok, tracer} = Contract.start([Fixture], checks: [Check.FunctionClauses], only: [mfa])
    assert Fixture.choose(1) == :one
    assert Fixture.choose(2) == :other
    assert Fixture.unrelated(3) == :unused
    coverage = Contract.stop(tracer)

    assert MapSet.new(coverage.clauses, & &1.id) == MapSet.new(clauses, & &1.id)
    assert Enum.map(coverage.arities, &{&1.module, &1.function, &1.arity}) == [mfa]
    assert coverage.arity_calls == %{mfa => 2}

    assert Enum.map(clauses, &coverage.clause_outcomes[&1.id]) == [
             %{selected: 1, head_matches: 1, guard_passes: 1, guard_rejections: 0},
             %{selected: 1, head_matches: 2, guard_passes: 2, guard_rejections: 0}
           ]
  end

  test "compiler selection admits a selected late function before the default function cap" do
    with_compiler_fixture(fn module ->
      {:ok, baseline} = Contract.start([module], checks: [Check.ElixirCompiler])
      apply(module, :f14, [:seen])
      baseline = Contract.stop(baseline)
      late = Enum.filter(baseline.compiler_return_alternatives, &(&1.function == :f14))
      assert length(late) == 2
      assert Enum.all?(late, &MapSet.member?(baseline.unknown, &1.id))
      refute Map.has_key?(baseline.compiler_calls, {module, :f14, 1})

      {:ok, tracer} =
        Contract.start([module], checks: [Check.ElixirCompiler], only: [{module, :f14, 1}])

      assert apply(module, :f14, [:seen]) == :seen
      assert apply(module, :f01, [:seen]) == :seen
      coverage = Contract.stop(tracer)

      assert MapSet.new(coverage.compiler_return_alternatives, & &1.id) ==
               MapSet.new(late, & &1.id)

      assert coverage.compiler_calls == %{{module, :f14, 1} => 1}
      assert Enum.empty?(coverage.unknown)
      assert Enum.empty?(coverage.compiler_warnings)
      assert Contract.summary(coverage).missed_compiler_return_alternatives == 1
    end)
  end

  test "earlier checks claim only selected return alternatives" do
    with_compiler_fixture(fn module ->
      for checks <- [
            [Check.Typespec, Check.ElixirCompiler],
            [Check.ElixirCompiler, Check.Typespec]
          ] do
        {:ok, tracer} = Contract.start([module], checks: checks, only: [{module, :f14, 1}])
        coverage = Contract.stop(tracer)

        {claims, _} =
          Enum.map_reduce(checks, MapSet.new(), fn check, earlier ->
            {:ok, state, plan} =
              check.init([module], [], %{claims: earlier, only: MapSet.new([{module, :f14, 1}])})

            try do
              {plan.claims, MapSet.union(earlier, plan.claims)}
            after
              check.terminate(state)
            end
          end)

        assert claims == [MapSet.new([{:return_alternatives, {module, :f14, 1}}]), MapSet.new()]
        targets = coverage.return_alternatives ++ coverage.compiler_return_alternatives
        assert length(targets) == 2
        assert Enum.all?(targets, &(&1.function == :f14))

        if hd(checks) == Check.Typespec do
          assert Enum.empty?(coverage.compiler_return_alternatives)
        else
          assert Enum.empty?(coverage.return_alternatives)
        end
      end
    end)
  end

  test "explicit empty selection starts no workers metadata loading or instrumentation" do
    absent = Bylaw.Contract.FunctionSelectionAbsentModule
    refute Code.loaded?(absent)

    {:ok, tracer} =
      Contract.start([Fixture, absent],
        checks: [Check.Typespec, Check.FunctionClauses, Check.ElixirCompiler],
        only: []
      )

    assert Enum.empty?(:sys.get_state(tracer).workers)
    coverage = Contract.stop(tracer)
    refute Code.loaded?(absent)
    assert coverage.checks == %{}
    assert Enum.empty?(coverage.input_classes)
    assert Enum.empty?(coverage.clauses)
    assert Enum.empty?(coverage.compiler_return_alternatives)
    assert Enum.empty?(coverage.warnings)
  end

  test "empty selection produces an explicit empty-scope diagnostic" do
    {:ok, tracer} = Contract.start([Fixture], only: [])
    coverage = Contract.stop(tracer)
    {:ok, output} = StringIO.open("")
    assert :ok = Contract.print_report(coverage, output, colors: false)
    {_, report} = StringIO.contents(output)
    assert report =~ "No functions selected for contract observation."
  end

  test "unselected modules remain unloaded during initialization" do
    unused = Bylaw.Contract.TestFixtures.SelectionUnloaded
    assert {:module, ^unused} = Code.ensure_loaded(unused)
    :code.purge(unused)
    assert :code.delete(unused)
    refute Code.loaded?(unused)
    on_exit(fn -> Code.ensure_loaded!(unused) end)

    {:ok, tracer} = Contract.start([unused, Fixture], only: [{Fixture, :choose, 1}])
    remains_unloaded = not Code.loaded?(unused)
    coverage = Contract.stop(tracer)
    assert remains_unloaded
    refute Code.loaded?(unused)
    assert Enum.all?(coverage.input_classes ++ coverage.clauses, &(&1.module == Fixture))
  end

  test "unselected function metadata is filtered before type expansion" do
    dependency = Bylaw.Contract.TestFixtures.SelectionUnloaded
    Code.ensure_loaded!(dependency)
    :code.purge(dependency)
    assert :code.delete(dependency)
    on_exit(fn -> Code.ensure_loaded!(dependency) end)

    {:ok, tracer} =
      Contract.start([Fixture], checks: [Check.Typespec], only: [{Fixture, :choose, 1}])

    unloaded = not Code.loaded?(dependency)
    Contract.stop(tracer)
    assert unloaded
    refute Code.loaded?(dependency)
    Specs.load([Fixture])
    assert Code.loaded?(dependency)
  end

  test "invalid selections and modules outside the supplied module list fail before startup" do
    for invalid <- [
          nil,
          false,
          :all,
          [Fixture],
          [{Fixture, :choose}],
          [{"module", :choose, 1}],
          [{Fixture, "choose", 1}],
          [{Fixture, :choose, -1}],
          [{Fixture, :choose, 256}]
        ] do
      assert_raise ArgumentError, ~r/:only.*list.*module.*function.*arity/, fn ->
        Contract.start([Fixture], only: invalid)
      end
    end

    assert_raise ArgumentError, ~r/supplied modules/, fn ->
      Contract.start([Fixture], only: [{__MODULE__, :outside, 0}])
    end
  end

  test "custom checks reject scoped mode and retain existing unscoped behavior" do
    checks = [{CustomCheck, notify: self()}]

    for selection <- [[], [{Fixture, :choose, 1}]] do
      assert_raise ArgumentError, ~r/does not support :only/, fn ->
        Contract.start([Fixture], checks: checks, only: selection)
      end

      refute_received {:custom_initialized, _, _}
    end

    {:ok, tracer} = Contract.start([Fixture], checks: checks)
    coverage = Contract.stop(tracer)
    assert_receive {:custom_initialized, [Fixture], %{claims: claims}}
    assert Enum.empty?(claims)
    assert coverage.checks == %{CustomCheck => %{}}
  end

  test "selected unsupported targets remain unassessable rather than missed" do
    fixture = Bylaw.Contract.Example.Partitions

    {:ok, tracer} =
      Contract.start([fixture], checks: [Check.Typespec], only: [{fixture, :opaque_shape, 1}])

    fixture.opaque_shape(1)
    coverage = Contract.stop(tracer)
    [target] = coverage.input_classes
    assert target.function == :opaque_shape
    assert MapSet.member?(coverage.unknown, target.id)
    assert Map.get(coverage.hits, target.id, 0) == 0
    assert Contract.summary(coverage).missed_input_classes == 0
  end

  test "scoped queue exhaustion retains incomplete status and the default queue limit" do
    {:ok, tracer} =
      Contract.start([Fixture], checks: [Check.Typespec], only: [{Fixture, :choose, 1}])

    [worker] = :sys.get_state(tracer).workers
    session = :sys.get_state(worker).session

    try do
      :sys.suspend(worker)
      for _ <- 1..5000, do: Fixture.choose(1)
      await_exhausted(session)
      :sys.resume(worker)
      coverage = Contract.stop(tracer)
      assert coverage.status == :incomplete

      assert Enum.any?(coverage.incomplete, fn reason ->
               reason.check == Check.Typespec and reason.reason == :trace_queue_limit and
                 reason.limit == 4096 and reason.observed > 4096
             end)

      assert Contract.summary(coverage).status == :incomplete
      refute Process.alive?(worker)
    after
      if Process.alive?(worker), do: :sys.resume(worker)
      if Process.alive?(tracer), do: Contract.stop(tracer)
    end
  end

  test "repeated scoped compiler observation restores code and releases sessions" do
    with_compiler_fixture(fn module ->
      original_md5 = module.module_info(:md5)

      for count <- [0, 2, 3] do
        {:ok, tracer} =
          Contract.start([module], checks: [Check.ElixirCompiler], only: [{module, :f14, 1}])

        [worker] = :sys.get_state(tracer).workers
        token = :sys.get_state(worker).runtime.state.observer_token

        if count > 0 do
          Task.async(fn -> for _ <- 1..count, do: apply(module, :f14, [:seen]) end)
          |> Task.await()
        end

        coverage = Contract.stop(tracer)
        assert module.module_info(:md5) == original_md5
        refute Process.alive?(worker)
        refute Process.alive?(tracer)
        assert Bylaw.Contract.CompilerObserver.counts(token) == %{}
        assert Map.get(coverage.compiler_calls, {module, :f14, 1}, 0) == count
        assert MapSet.size(coverage.unknown) == if(count == 0, do: 2, else: 0)
        assert apply(module, :f14, [:other]) == :other
        assert Bylaw.Contract.CompilerObserver.counts(token) == %{}
      end
    end)
  end

  test "explicit default arities retain the selected callable scope" do
    fixture = Bylaw.Contract.TestFixtures.SelectionDefaults

    for arity <- [1, 2] do
      mfa = {fixture, :defaulted, arity}
      {:ok, tracer} = Contract.start([fixture], checks: [Check.FunctionClauses], only: [mfa])
      assert fixture.defaulted(:first) == {:brief, :first}
      assert fixture.defaulted(:second, :long) == {:long, :second}
      coverage = Contract.stop(tracer)
      assert Enum.map(coverage.arities, &{&1.module, &1.function, &1.arity}) == [mfa]
      assert coverage.arity_calls == %{mfa => arity}

      if arity == 1 do
        assert Enum.empty?(coverage.clauses)
        assert [%{default_wrapper?: true, authored?: false}] = coverage.arities
      else
        assert [%{arity: 2, function: :defaulted}] = coverage.clauses
        assert [%{default_wrapper?: false, authored?: true}] = coverage.arities
      end
    end
  end

  defp await_exhausted(session, attempts \\ 200)

  defp await_exhausted(_session, 0),
    do: flunk("selected trace session exceeded its shutdown deadline")

  defp await_exhausted(session, attempts) do
    :trace.info(session, self(), :flags)
    Process.sleep(5)
    await_exhausted(session, attempts - 1)
  catch
    :error, :badarg -> :ok
  end

  defp with_compiler_fixture(assertion) do
    module = Module.concat(__MODULE__, "Compiler#{System.unique_integer([:positive])}")
    directory = Path.join(System.tmp_dir!(), Atom.to_string(module))
    File.mkdir_p!(directory)

    definitions =
      Enum.map_join(1..14, "\n", fn index ->
        function = "f" <> String.pad_leading(Integer.to_string(index), 2, "0")

        "@spec #{function}(:seen | :other) :: :seen | :other\ndef #{function}(:seen), do: :seen\ndef #{function}(:other), do: :other"
      end)

    previous_options = Code.compiler_options()

    binary =
      try do
        Code.compiler_options(debug_info: true, infer_signatures: [:elixir])

        [{^module, binary}] =
          Code.compile_string("defmodule #{inspect(module)} do\n#{definitions}\nend")

        binary
      after
        Code.compiler_options(previous_options)
      end

    path = Path.join(directory, "#{module}.beam")
    File.write!(path, binary)
    :code.purge(module)
    :code.delete(module)
    Code.prepend_path(directory)
    {:module, ^module} = :code.load_abs(String.to_charlist(Path.rootname(path)))

    try do
      assertion.(module)
    after
      :code.purge(module)
      :code.delete(module)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end
  end
end
