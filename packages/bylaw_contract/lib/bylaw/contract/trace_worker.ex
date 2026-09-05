defmodule Bylaw.Contract.TraceWorker do
  @moduledoc false
  use GenServer
  alias Bylaw.Contract.TraceQueueBudget

  @return_trace_match_spec [{:_, [], [{:return_trace}]}]
  @return_only_trace_match_spec [{:_, [], [{:return_trace}, {:message, false}]}]

  @doc false
  @spec start_link(
          modules :: list(module()),
          check :: module(),
          opts :: list(),
          claims :: MapSet.t(),
          max_trace_queue :: pos_integer()
        ) :: GenServer.on_start()
  def start_link(modules, check, opts, claims, limit \\ 4096),
    do: GenServer.start_link(__MODULE__, {modules, check, opts, claims, limit})

  @doc false
  @spec claims(worker :: GenServer.server()) :: MapSet.t()
  def claims(worker), do: GenServer.call(worker, :claims, :infinity)

  @doc false
  @spec activate(worker :: GenServer.server()) :: :ok | {:error, term()}
  def activate(worker), do: GenServer.call(worker, :activate, :infinity)

  @spec stop(worker :: GenServer.server()) :: {module(), map()}
  def stop(worker), do: GenServer.call(worker, :stop, :infinity)

  @spec start_observation_window(worker :: GenServer.server()) :: :ok
  def start_observation_window(worker), do: GenServer.cast(worker, :start_observation_window)

  @spec ex_unit_test_started(worker :: GenServer.server(), label :: term()) :: :ok
  def ex_unit_test_started(worker, label),
    do: GenServer.cast(worker, {:ex_unit_test_started, label})

  @spec ex_unit_test_finished(worker :: GenServer.server(), label :: term()) :: :ok
  def ex_unit_test_finished(worker, label),
    do: GenServer.cast(worker, {:ex_unit_test_finished, label})

  @impl GenServer
  def init({modules, check, opts, claims, limit}) do
    Process.flag(:trap_exit, true)
    Process.flag(:message_queue_data, :off_heap)

    case check.init(modules, opts, %{claims: claims}) do
      {:ok, check_state, plan} ->
        runtime = %{
          module: check,
          observes_caller?: function_exported?(check, :observe, 3),
          queue_limit: limit,
          state: check_state,
          calls: plan.calls,
          returns: plan.returns,
          process_scope: Map.get(plan, :process_scope, :all),
          trace_scope: Map.get(plan, :trace_scope, :local)
        }

        {:ok, %{runtime: runtime, session: nil, claims: plan.claims}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  defp start_runtime(runtime) do
    if Enum.empty?(runtime.calls) and Enum.empty?(runtime.returns) do
      {:ok,
       %{
         budget: nil,
         transport: :passive,
         session: nil,
         active_test_labels: %{},
         traced_test_processes: MapSet.new(),
         scan_timer: nil,
         patterns_configured?: true,
         runtime: runtime
       }}
    else
      start_process_worker(runtime)
    end
  end

  defp start_process_worker(runtime) do
    with {:ok, session} <- start_trace_session(runtime) do
      {:ok,
       %{
         budget: TraceQueueBudget.start(self(), session, runtime.queue_limit),
         transport: :process,
         session: session,
         active_test_labels: %{},
         traced_test_processes: MapSet.new(),
         scan_timer: nil,
         patterns_configured?: runtime.process_scope != :ex_unit_tests,
         runtime: runtime
       }}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl GenServer
  def handle_info({:trace, caller, :call, {module, function, arguments}}, state)
      when is_list(arguments) do
    event = {:call, {module, function, Enum.count(arguments)}, arguments}
    {:noreply, observe(event, caller, state)}
  end

  def handle_info({:trace, caller, :return_from, mfa, value}, state) do
    {:noreply, observe({:return, mfa, value}, caller, state)}
  end

  def handle_info(:scan_ex_unit_processes, state) do
    state = %{state | scan_timer: nil}
    {:noreply, state |> trace_labeled_test_processes() |> schedule_test_process_scan()}
  end

  def handle_info({:EXIT, _process, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _process, reason}, state), do: {:stop, reason, state}

  def handle_info(_, state), do: {:noreply, state}

  @impl GenServer
  def handle_cast(:start_observation_window, state) do
    {:noreply, configure_runtime_patterns(state)}
  end

  def handle_cast(
        {:ex_unit_test_started, label},
        %{runtime: %{process_scope: :ex_unit_tests}} = state
      ) do
    active_test_labels = Map.update(state.active_test_labels, label, 1, &(&1 + 1))

    {:noreply,
     %{state | active_test_labels: active_test_labels}
     |> trace_labeled_test_processes()
     |> schedule_test_process_scan()}
  end

  def handle_cast(
        {:ex_unit_test_finished, label},
        %{runtime: %{process_scope: :ex_unit_tests}} = state
      ) do
    {:noreply, %{state | active_test_labels: decrement_label(state.active_test_labels, label)}}
  end

  def handle_cast(_message, state), do: {:noreply, state}

  @impl GenServer
  def handle_call(:claims, _, state) do
    {:reply, state.claims, Map.delete(state, :claims)}
  end

  def handle_call(:activate, _, state) do
    case start_runtime(state.runtime) do
      {:ok, activated} -> {:reply, :ok, activated}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:stop, _, state) do
    TraceQueueBudget.stop(state.budget)
    state = stop_trace(state)
    coverage = state.runtime.module.coverage(state.runtime.state)
    reasons = TraceQueueBudget.reason(state.budget, state.runtime.module)

    coverage =
      if Enum.any?(reasons) do
        Map.put(coverage, :incomplete, reasons)
      else
        coverage
      end

    state.runtime.module.terminate(state.runtime.state)

    {:stop, :normal, {state.runtime.module, coverage},
     %{state | session: nil, runtime: nil, budget: nil}}
  end

  @impl GenServer
  def terminate(_, state) do
    TraceQueueBudget.stop(Map.get(state, :budget))
    destroy_session(Map.get(state, :session))

    if state.runtime do
      state.runtime.module.terminate(state.runtime.state)
    end

    :ok
  end

  defp observe(event, caller, state) do
    runtime = state.runtime

    if TraceQueueBudget.check(state.budget, 1) == 0 and observes?(runtime, event) do
      result =
        if runtime.observes_caller? do
          runtime.module.observe(event, caller, runtime.state)
        else
          runtime.module.observe(event, runtime.state)
        end

      apply_result(result, state)
    else
      state
    end
  end

  defp apply_result({:complete, check_state, completed}, state) when is_list(completed) do
    runtime = Enum.reduce(completed, %{state.runtime | state: check_state}, &retire/2)

    completed
    |> Enum.map(&elem(&1, 1))
    |> Enum.uniq()
    |> Enum.each(&update_trace_function(state.session, runtime, &1))

    %{state | runtime: runtime}
  end

  defp apply_result(check_state, state), do: put_in(state.runtime.state, check_state)

  defp observes?(runtime, {:call, mfa, _arguments}), do: MapSet.member?(runtime.calls, mfa)

  defp observes?(runtime, {:return, mfa, _value}), do: MapSet.member?(runtime.returns, mfa)

  defp retire({:return, mfa}, runtime),
    do: %{runtime | returns: MapSet.delete(runtime.returns, mfa)}

  defp retire({:call, mfa}, runtime), do: %{runtime | calls: MapSet.delete(runtime.calls, mfa)}

  defp update_trace_function(session, runtime, mfa) do
    :trace.function(
      session,
      mfa,
      trace_match_spec(mfa, runtime.calls, runtime.returns),
      trace_pattern_flags(runtime.trace_scope)
    )

    :ok
  catch
    :error, :badarg -> :ok
  end

  defp start_trace_session(runtime) do
    with {:ok, session} <- create_session() do
      configure_session(session, runtime)
    end
  end

  defp create_session do
    {:ok, :trace.session_create(:bylaw_contract_check, self(), [])}
  rescue
    error in ArgumentError ->
      {:error,
       "could not create a Bylaw.Contract isolated trace session: #{Exception.message(error)}"}
  end

  defp configure_session(session, runtime) do
    if runtime.process_scope != :ex_unit_tests do
      configure_patterns(session, runtime.calls, runtime.returns, runtime.trace_scope)
    end

    configure_process_scope(session, runtime.process_scope)
    {:ok, session}
  rescue
    error in ArgumentError ->
      destroy_session(session)

      {:error,
       "could not configure a Bylaw.Contract isolated trace session: #{Exception.message(error)}"}
  end

  defp configure_patterns(session, call_mfas, return_mfas, trace_scope) do
    call_mfas
    |> MapSet.union(return_mfas)
    |> Enum.each(fn mfa ->
      :trace.function(
        session,
        mfa,
        trace_match_spec(mfa, call_mfas, return_mfas),
        trace_pattern_flags(trace_scope)
      )
    end)
  end

  defp configure_process_scope(_session, :ex_unit_tests), do: :ok

  defp configure_process_scope(session, process_scope),
    do: :trace.process(session, process_scope, true, [:call])

  defp trace_match_spec(mfa, call_mfas, return_mfas) do
    case {MapSet.member?(call_mfas, mfa), MapSet.member?(return_mfas, mfa)} do
      {true, true} -> @return_trace_match_spec
      {false, true} -> @return_only_trace_match_spec
      {true, false} -> true
      {false, false} -> false
    end
  end

  defp trace_pattern_flags(:local), do: [:local]
  defp trace_pattern_flags(:global), do: []

  defp stop_trace(%{session: nil} = state), do: state

  defp stop_trace(%{session: session} = state) do
    cancel_process_scan(state.scan_timer)

    state =
      if TraceQueueBudget.check(state.budget) == 0 do
        reference = :trace.delivered(session, :all)
        :trace.process(session, :all, false, [:call])
        drain_trace(state, reference)
      else
        state
      end

    destroy_session(session)
    %{state | session: nil}
  end

  defp drain_trace(state, reference) do
    if TraceQueueBudget.check(state.budget) > 0 do
      state
    else
      receive do
        {:trace_delivered, :all, ^reference} ->
          state

        {:trace, _, :call, {_, _, arguments}} = message when is_list(arguments) ->
          {:noreply, state} = handle_info(message, state)
          drain_trace(state, reference)

        {:trace, _, :return_from, {_, _, _}, _} = message ->
          {:noreply, state} = handle_info(message, state)
          drain_trace(state, reference)

        _ ->
          drain_trace(state, reference)
      end
    end
  end

  defp trace_labeled_test_processes(%{runtime: %{process_scope: :ex_unit_tests}} = state) do
    test_processes =
      Process.list()
      |> Enum.reject(&MapSet.member?(state.traced_test_processes, &1))
      |> Enum.filter(&active_test_process?(&1, state.active_test_labels))

    Enum.each(test_processes, fn test_process ->
      :trace.process(state.session, test_process, true, [:call])
    end)

    %{
      state
      | traced_test_processes:
          MapSet.union(state.traced_test_processes, MapSet.new(test_processes))
    }
  catch
    :error, :badarg -> state
  end

  defp trace_labeled_test_processes(state), do: state

  defp active_test_process?(process, active_test_labels) do
    case Process.info(process, :label) do
      {:label, label} -> Map.has_key?(active_test_labels, label)
      _ -> false
    end
  end

  defp schedule_test_process_scan(%{scan_timer: nil, active_test_labels: labels} = state)
       when map_size(labels) > 0 do
    %{state | scan_timer: Process.send_after(self(), :scan_ex_unit_processes, 2)}
  end

  defp schedule_test_process_scan(state), do: state

  defp cancel_process_scan(nil), do: :ok
  defp cancel_process_scan(timer), do: Process.cancel_timer(timer)

  defp decrement_label(labels, label) do
    case Map.get(labels, label) do
      nil -> labels
      1 -> Map.delete(labels, label)
      count -> Map.put(labels, label, count - 1)
    end
  end

  defp configure_runtime_patterns(%{patterns_configured?: true} = state), do: state

  defp configure_runtime_patterns(state) do
    runtime = state.runtime

    if TraceQueueBudget.check(state.budget) == 0 do
      configure_patterns(state.session, runtime.calls, runtime.returns, runtime.trace_scope)
      %{state | patterns_configured?: true}
    else
      state
    end
  catch
    :error, :badarg ->
      if TraceQueueBudget.check(state.budget) > 0 do
        state
      else
        :erlang.error(:badarg)
      end
  end

  defp destroy_session(nil), do: :ok

  defp destroy_session(session) do
    :trace.session_destroy(session)
  catch
    :error, :badarg -> :ok
  end
end
