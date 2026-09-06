defmodule BylawOwnershipAdapter do
  @moduledoc false
  use GenServer

  @doc false
  @spec start_link(pid()) :: GenServer.on_start()
  def start_link(worker), do: GenServer.start_link(__MODULE__, worker, name: __MODULE__)

  @doc false
  @spec register(pid()) :: :ok | {:error, term()}
  def register(pid), do: GenServer.call(__MODULE__, {:register, pid})

  @impl GenServer
  def init(worker) do
    ref = Process.monitor(worker)

    :sys.replace_state(worker, fn state ->
      true = is_nil(state.scan_timer)
      put_in(state.runtime.process_scope, :qa_explicit_roots)
    end)

    {:ok, %{worker: worker, worker_ref: ref, roots: %{}, count: 0, peak: 0, times: []}}
  end

  @impl GenServer
  def handle_call({:register, pid}, _from, state) do
    started = System.monotonic_time(:microsecond)

    result =
      :sys.replace_state(state.worker, fn worker ->
        result =
          if Bylaw.Contract.TraceQueueBudget.check(worker.budget) == 0 do
            try do
              if Process.alive?(pid) do
                :trace.process(worker.session, pid, true, [:call])
                :ok
              else
                {:error, :dead_process}
              end
            catch
              :error, :badarg -> {:error, :closed_session}
            end
          else
            {:error, :incomplete}
          end

        worker =
          if result == :ok,
            do: Map.update!(worker, :traced_test_processes, &MapSet.put(&1, pid)),
            else: worker

        Map.put(worker, :qa_registration_result, result)
      end)
      |> Map.fetch!(:qa_registration_result)

    elapsed = System.monotonic_time(:microsecond) - started

    state =
      if result == :ok and not Map.has_key?(state.roots, pid) do
        %{
          state
          | roots: Map.put(state.roots, pid, Process.monitor(pid)),
            count: state.count + 1,
            peak: max(state.peak, map_size(state.roots) + 1)
        }
      else
        state
      end

    {:reply, result, %{state | times: [elapsed | state.times]}}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply,
     %{
       count: state.count,
       retained: map_size(state.roots),
       peak: state.peak,
       times_us: state.times
     }, state}
  end

  @impl GenServer
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{worker_ref: ref} = state),
    do: {:stop, :normal, state}

  def handle_info({:DOWN, ref, :process, pid, _reason}, state) do
    if Map.get(state.roots, pid) == ref do
      :sys.replace_state(state.worker, fn worker ->
        Map.update!(worker, :traced_test_processes, &MapSet.delete(&1, pid))
      end)

      {:noreply, %{state | roots: Map.delete(state.roots, pid)}}
    else
      {:noreply, state}
    end
  end

  @impl GenServer
  def terminate(_reason, state) do
    Enum.each(state.roots, fn {_pid, ref} -> Process.demonitor(ref, [:flush]) end)
    :ok
  end
end
