# Diagnostic proxy: execute the real formatter callbacks and capture stop's return
# using an isolated trace session limited to this formatter process.
defmodule BylawWarmLifecycleCapture do
  use GenServer
  alias Bylaw.Contract.ExUnitFormatter

  @impl GenServer
  def init(options) do
    started = System.monotonic_time(:microsecond)
    owner = self()
    collector = spawn_link(fn -> collect(owner) end)
    trace = :trace.session_create(:warm_capture, collector, [])
    Code.ensure_loaded!(Bylaw.Contract.Tracer)

    :trace.function(trace, {Bylaw.Contract.Tracer, :stop, 1}, [{:_, [], [{:return_trace}]}], [
      :local
    ])

    :trace.process(trace, self(), true, [:call])
    {:ok, delegate} = ExUnitFormatter.init(options)
    init_us = System.monotonic_time(:microsecond) - started
    resources = resources(delegate.tracer)
    :persistent_term.put({__MODULE__, :resources}, resources)

    {:ok,
     %{
       delegate: delegate,
       trace: trace,
       resources: resources,
       init_us: init_us,
       collector: collector
     }}
  end

  @impl GenServer
  def handle_cast({:suite_finished, _} = event, state) do
    started = System.monotonic_time(:microsecond)
    {:noreply, delegate} = ExUnitFormatter.handle_cast(event, state.delegate)

    coverage =
      if is_pid(state.delegate.tracer) do
        receive do
          {:warm_coverage, coverage} -> coverage
        after
          5_000 -> raise "real formatter stop did not return a capture"
        end
      end

    stop_us = System.monotonic_time(:microsecond) - started
    :trace.session_destroy(state.trace)
    stop_collector(state.collector)
    :persistent_term.erase({__MODULE__, :resources})
    refs = state.resources

    cleanup = %{
      processes: Enum.all?(refs.processes ++ [state.collector], &(not Process.alive?(&1))),
      sessions: Enum.all?(refs.sessions, &session_gone?/1),
      shadows: Enum.all?(refs.shadows, &(:code.is_loaded(&1) == false))
    }

    cleanup = Map.put(cleanup, :all_released, Enum.all?(Map.values(cleanup)))

    result = %{
      coverage: coverage,
      observer: inspect(state.delegate.tracer),
      workers: Enum.map(refs.workers, &inspect/1),
      cleanup: cleanup,
      init_us: state.init_us,
      stop_us: stop_us,
      completion: if(delegate.completion, do: :atomics.get(delegate.completion, 1)),
      error: delegate.error,
      hooks: hook_count()
    }

    File.write!(System.fetch_env!("BYLAW_WARM_CAPTURE"), :erlang.term_to_binary(result))
    {:noreply, %{state | delegate: delegate, trace: nil}}
  end

  def handle_cast(event, state) do
    {:noreply, delegate} = ExUnitFormatter.handle_cast(event, state.delegate)
    {:noreply, %{state | delegate: delegate}}
  end

  @impl GenServer
  def terminate(reason, state) do
    ExUnitFormatter.terminate(reason, state.delegate)
    if state.trace, do: :trace.session_destroy(state.trace)
    stop_collector(state.collector)
    :persistent_term.erase({__MODULE__, :resources})
  end

  @doc false
  @spec overflow() :: :ok
  def overflow do
    resources = :persistent_term.get({__MODULE__, :resources})
    for worker <- resources.workers, do: :sys.suspend(worker)

    try do
      for _ <- 1..300, do: BylawPhaseFixture.Classifier1.classify(1)

      for budget <- resources.budgets do
        await_overflow(budget, 200)
      end
    after
      for worker <- resources.workers, Process.alive?(worker), do: :sys.resume(worker)
    end

    :ok
  end

  @doc false
  @spec hook_count() :: non_neg_integer()
  def hook_count do
    # Read-only diagnostic of the installed Elixir version, not a supported API.
    :elixir_config.get(:at_exit)
    |> Enum.count(fn function ->
      :erlang.fun_info(function, :module) == {:module, ExUnitFormatter}
    end)
  end

  defp await_overflow(_budget, 0), do: raise("observer did not exhaust its queue budget")

  defp await_overflow(budget, remaining) do
    if Bylaw.Contract.TraceQueueBudget.check(budget) == 0 do
      Process.sleep(5)
      await_overflow(budget, remaining - 1)
    end
  end

  defp collect(owner) do
    receive do
      {:trace, _, :return_from, {Bylaw.Contract.Tracer, :stop, 1}, coverage} ->
        send(owner, {:warm_coverage, coverage})
        collect(owner)

      :stop ->
        :ok

      _ ->
        collect(owner)
    end
  end

  defp stop_collector(collector) do
    monitor = Process.monitor(collector)
    send(collector, :stop)

    receive do
      {:DOWN, ^monitor, :process, ^collector, _} -> :ok
    after
      5_000 -> raise "capture collector did not stop"
    end
  end

  defp resources(nil), do: %{workers: [], processes: [], sessions: [], shadows: [], budgets: []}

  defp resources(tracer) do
    workers = :sys.get_state(tracer).workers
    states = Enum.map(workers, &:sys.get_state/1)
    budgets = for state <- states, state.budget, do: state.budget

    %{
      workers: workers,
      processes: [tracer | workers] ++ Enum.map(budgets, & &1.pid),
      sessions: for(state <- states, state.session, do: state.session),
      shadows:
        for(state <- states, shadow = Map.get(state.runtime.state, :shadow), shadow, do: shadow),
      budgets: budgets
    }
  end

  defp session_gone?(session) do
    :trace.info(session, self(), :flags)
    false
  rescue
    ArgumentError -> true
  end
end
