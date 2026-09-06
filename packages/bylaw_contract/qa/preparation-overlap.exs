# QA-only native Mix require gate. Load only into a dedicated fresh command VM.
defmodule BylawPreparationGate do
  @moduledoc false
  use GenServer

  @doc false
  @spec event(atom(), map()) :: :ok
  def event(name, details \\ %{}) do
    row = %{name: name, details: details, at_us: System.monotonic_time(:microsecond)}
    GenServer.call(__MODULE__, {:event, row})
  end

  @doc false
  @spec memory() :: map()
  def memory, do: Map.new(:erlang.memory([:total, :processes, :binary, :code, :ets]))

  @doc false
  @spec own(pid()) :: :ok
  def own(tracer), do: GenServer.call(__MODULE__, {:own, tracer})

  @doc false
  @spec owner(pid()) :: :ok
  def owner(pid), do: GenServer.call(__MODULE__, {:owner, pid})

  @doc false
  @spec ready() :: :ok
  def ready, do: GenServer.call(__MODULE__, {:phase, :ready})

  @doc false
  @spec failed(term()) :: :ok
  def failed(reason), do: GenServer.call(__MODULE__, {:phase, {:failed, inspect(reason)}})

  @doc false
  @spec await_ready(integer()) :: :ok
  def await_ready(deadline \\ System.monotonic_time(:millisecond) + 60_000) do
    case GenServer.call(__MODULE__, :phase) do
      phase when phase in [:ready, :finished] ->
        :ok

      {:failed, reason} ->
        raise "preparation failed before requiring tests: #{reason}"

      :pending ->
        if System.monotonic_time(:millisecond) >= deadline,
          do: raise("preparation gate timed out")

        Process.sleep(1)
        await_ready(deadline)
    end
  end

  @doc false
  @spec require_tests(list(Path.t()), keyword()) :: term()
  def require_tests(files, options) do
    if System.fetch_env!("BYLAW_PREPARATION_LAYOUT") == "serialized", do: await_ready()

    event(:require_started, %{
      files: length(files),
      paths: Enum.map(files, &Path.expand/1),
      memory: memory(),
      compiler_options:
        Map.take(Code.compiler_options(), [:docs, :debug_info, :infer_signatures]),
      max_requires:
        Keyword.get(options, :max_concurrency, max(:erlang.system_info(:schedulers_online), 2))
    })

    try do
      Kernel.ParallelCompiler.require(files, options)
    after
      event(:require_finished, %{memory: memory()})
    end
  end

  @doc false
  @spec shadows() :: list(String.t())
  def shadows do
    for {module, _} <- :code.all_loaded(),
        String.starts_with?(
          Atom.to_string(module),
          "Elixir.Bylaw.Contract.StructuralCoverage.Shadow"
        ),
        do: Atom.to_string(module)
  end

  @doc false
  @spec await_worker_shutdown(integer()) :: list(pid())
  def await_worker_shutdown(deadline) do
    workers =
      for pid <- Process.list(),
          {:dictionary, dictionary} <- [Process.info(pid, :dictionary)],
          Keyword.get(dictionary, :"$initial_call") in [
            {Bylaw.Contract.Tracer, :init, 1},
            {Bylaw.Contract.TraceWorker, :init, 1}
          ],
          do: pid

    if Enum.empty?(workers) or System.monotonic_time(:millisecond) >= deadline do
      workers
    else
      Process.sleep(1)
      await_worker_shutdown(deadline)
    end
  end

  @impl GenServer
  def init(_), do: {:ok, %{phase: :pending, events: [], owned: [], owner_ref: nil}}
  @impl GenServer
  def handle_call({:event, row}, _, state) do
    phase = if row.name == :stopped, do: :finished, else: state.phase
    {:reply, :ok, %{state | phase: phase, events: [row | state.events]}}
  end

  def handle_call({:owner, pid}, _, state),
    do: {:reply, :ok, %{state | owner_ref: Process.monitor(pid)}}

  def handle_call({:phase, phase}, _, state), do: {:reply, :ok, %{state | phase: phase}}

  def handle_call({:own, tracer}, _, state),
    do: {:reply, :ok, %{state | owned: [tracer | state.owned]}}

  def handle_call(:phase, _, state), do: {:reply, state.phase, state}
  def handle_call(:snapshot, _, state), do: {:reply, state, state}

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _, reason}, %{owner_ref: ref} = state) do
    phase = if state.phase == :finished, do: :finished, else: {:failed, inspect(reason)}

    row = %{
      name: :preparation_owner_down,
      at_us: System.monotonic_time(:microsecond),
      details: %{reason: inspect(reason)}
    }

    {:noreply, %{state | phase: phase, events: [row | state.events]}}
  end
end

defmodule BylawPreparationFailureCheck do
  @behaviour Bylaw.Contract.Check
  @impl Bylaw.Contract.Check
  def init(_, _, _) do
    BylawPreparationGate.event(:failure_check_reached, %{
      shadow_count: length(BylawPreparationGate.shadows())
    })

    {:error, "retained initialization failure"}
  end

  @impl Bylaw.Contract.Check
  def observe(_, state), do: state
  @impl Bylaw.Contract.Check
  def coverage(_), do: %{}
  @impl Bylaw.Contract.Check
  def terminate(_), do: :ok
end

defmodule BylawPreparationCapture do
  @moduledoc false
  use GenServer

  @impl GenServer
  def init(options) do
    BylawPreparationGate.owner(self())
    started = System.monotonic_time(:microsecond)
    BylawPreparationGate.event(:preparation_started, %{memory: BylawPreparationGate.memory()})
    Code.prepend_path(System.fetch_env!("BYLAW_OVERHEAD_EBIN"))

    checks =
      if System.get_env("BYLAW_PREPARATION_SCENARIO") == "init_failure",
        do: [Bylaw.Contract.Check.FunctionClauses, BylawPreparationFailureCheck],
        else: [Bylaw.Contract.Check.Typespec, Bylaw.Contract.Check.FunctionClauses]

    try do
      {:ok, delegate} =
        Bylaw.Contract.ExUnitFormatter.init(Keyword.put(options, :bylaw_contract, checks: checks))

      if is_pid(delegate.tracer) do
        BylawPreparationGate.own(delegate.tracer)
        workers = :sys.get_state(delegate.tracer).workers

        BylawPreparationGate.event(:prepared, %{
          workers: length(workers),
          memory: BylawPreparationGate.memory()
        })

        BylawPreparationGate.ready()
      else
        BylawPreparationGate.failed(delegate.error)
      end

      {:ok,
       %{
         delegate: delegate,
         init_started: started,
         init_us: System.monotonic_time(:microsecond) - started,
         suite_started: nil,
         test_states: %{},
         test_identities: [],
         failures: [],
         test_times: [],
         compiler_options:
           Map.take(Code.compiler_options(), [:docs, :debug_info, :infer_signatures]),
         options: Keyword.take(options, [:seed, :max_cases, :include, :exclude])
       }}
    catch
      kind, reason ->
        BylawPreparationGate.failed({kind, reason})
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end

  @impl GenServer
  def handle_cast({:suite_started, _} = event, state) do
    BylawPreparationGate.event(:suite_started)
    {:noreply, delegate(event, %{state | suite_started: System.monotonic_time(:microsecond)})}
  end

  def handle_cast({:test_started, _} = event, state), do: {:noreply, delegate(event, state)}

  def handle_cast({:test_finished, test} = event, state) do
    status = if is_tuple(test.state), do: elem(test.state, 0), else: test.state || :passed

    state = %{
      state
      | test_times: [test.time | state.test_times],
        test_identities: [{test.module, test.name, test.tags.line} | state.test_identities]
    }

    state = update_in(state.test_states, &Map.update(&1, status, 1, fn n -> n + 1 end))

    state =
      if test.state,
        do: %{state | failures: [{test.module, test.name, test.state} | state.failures]},
        else: state

    {:noreply, delegate(event, state)}
  end

  def handle_cast({:suite_finished, _}, %{delegate: %{tracer: nil, error: error}} = state) do
    BylawPreparationGate.failed(error)
    {:noreply, state}
  end

  def handle_cast({:suite_finished, timings}, state) do
    started = System.monotonic_time(:microsecond)
    BylawPreparationGate.event(:stop_started, %{memory: BylawPreparationGate.memory()})
    coverage = Bylaw.Contract.stop(state.delegate.tracer)
    finished = System.monotonic_time(:microsecond)
    BylawPreparationGate.event(:stopped, %{memory: BylawPreparationGate.memory()})

    {:ok, device} = StringIO.open("")
    Bylaw.Contract.Report.print(coverage, device, false)
    {:ok, {_, report}} = StringIO.close(device)
    report_sha256 = :crypto.hash(:sha256, report) |> Base.encode16()

    result = %{
      report_sha256: report_sha256,
      mode: "defaults",
      elixir: System.version(),
      otp: System.otp_release(),
      init_us: state.init_us,
      stop_us: finished - started,
      options: state.options,
      observed_suite_us: started - state.suite_started,
      ex_unit_timings: timings,
      test_states: state.test_states,
      failures: Enum.reverse(state.failures),
      test_identities: Enum.reverse(state.test_identities),
      test_times_us: Enum.reverse(state.test_times),
      compiler_options: state.compiler_options,
      coverage: coverage,
      monotonic_boundaries_us: %{
        init_started: state.init_started,
        init_finished: state.init_started + state.init_us,
        suite_started: state.suite_started,
        stop_started: started,
        stop_finished: finished
      }
    }

    File.write!(System.fetch_env!("BYLAW_OVERHEAD_OUTPUT"), :erlang.term_to_binary(result))
    {:noreply, %{state | delegate: nil}}
  end

  def handle_cast(event, state), do: {:noreply, delegate(event, state)}

  @impl GenServer
  def terminate(reason, %{delegate: delegate}) when not is_nil(delegate),
    do: Bylaw.Contract.ExUnitFormatter.terminate(reason, delegate)

  def terminate(_, _), do: :ok

  defp delegate(_event, %{delegate: nil} = state), do: state

  defp delegate(event, state) do
    {:noreply, updated} = Bylaw.Contract.ExUnitFormatter.handle_cast(event, state.delegate)
    %{state | delegate: updated}
  end
end

true = System.fetch_env!("BYLAW_PREPARATION_LAYOUT") in ["normal", "serialized"]
{:ok, gate} = GenServer.start(BylawPreparationGate, nil, name: BylawPreparationGate)
initial_options = Code.compiler_options()

System.at_exit(fn status ->
  snapshot = GenServer.call(gate, :snapshot)
  fallback_stops = Enum.filter(snapshot.owned, &Process.alive?/1)

  Enum.each(fallback_stops, fn tracer ->
    try do
      Bylaw.Contract.stop(tracer)
    catch
      :exit, _ -> :ok
    end
  end)

  cleanup_started = System.monotonic_time(:microsecond)

  workers =
    BylawPreparationGate.await_worker_shutdown(System.monotonic_time(:millisecond) + 2_000)

  cleanup_wait_us = System.monotonic_time(:microsecond) - cleanup_started
  owned_alive = Enum.filter(snapshot.owned, &Process.alive?/1)

  shadows = BylawPreparationGate.shadows()
  sessions = :trace.session_info(:all)

  clean =
    Enum.empty?(owned_alive) and Enum.empty?(workers) and Enum.empty?(shadows) and
      sessions == [legacy: :default]

  audit = %{
    layout: System.fetch_env!("BYLAW_PREPARATION_LAYOUT"),
    status: status,
    events: Enum.reverse(snapshot.events),
    phase: inspect(snapshot.phase),
    cleanup: %{
      clean: clean,
      workers: Enum.map(workers, &inspect/1),
      wait_us: cleanup_wait_us,
      shadows: shadows,
      sessions: inspect(sessions),
      fallback_stops: length(fallback_stops),
      compiler_options_restored: Code.compiler_options() == initial_options
    }
  }

  File.write!(System.fetch_env!("BYLAW_PREPARATION_OUTPUT"), JSON.encode!(audit))
  GenServer.stop(gate)
  if (not clean or match?({:failed, _}, snapshot.phase)) and status == 0, do: exit({:shutdown, 2})
end)

mix_source = Path.join(to_string(:code.lib_dir(:mix)), "lib/mix/compilers/test.ex")
mix_ast = mix_source |> File.read!() |> Code.string_to_quoted!(file: mix_source)

mix_ast =
  Macro.postwalk(mix_ast, fn
    {{:., _, [{:__aliases__, _, [:Kernel, :ParallelCompiler]}, :require]}, _, [files, options]} ->
      quote do: BylawPreparationGate.require_tests(unquote(files), unquote(options))

    other ->
      other
  end)

try do
  Code.compiler_options(ignore_module_conflict: true)
  Code.compile_quoted(mix_ast, mix_source)
after
  Code.compiler_options(initial_options)
end
