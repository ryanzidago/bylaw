defmodule Bylaw.Contract.Tracer do
  @moduledoc false
  use GenServer

  alias Bylaw.Contract.Check
  alias Bylaw.Contract.TraceWorker

  @spec start_link(
          modules :: list(module()),
          checks :: list({module(), Check.opts()})
        ) :: GenServer.on_start()
  def start_link(modules, checks), do: GenServer.start_link(__MODULE__, {modules, checks})

  @spec stop(tracer :: GenServer.server()) :: map()
  def stop(tracer), do: GenServer.call(tracer, :stop, :infinity)

  @spec start_observation_window(tracer :: GenServer.server()) :: :ok
  def start_observation_window(tracer), do: GenServer.cast(tracer, :start_observation_window)

  @spec ex_unit_test_started(tracer :: GenServer.server(), label :: term()) :: :ok
  def ex_unit_test_started(tracer, label),
    do: GenServer.cast(tracer, {:ex_unit_test_started, label})

  @spec ex_unit_test_finished(tracer :: GenServer.server(), label :: term()) :: :ok
  def ex_unit_test_finished(tracer, label),
    do: GenServer.cast(tracer, {:ex_unit_test_finished, label})

  @impl GenServer
  def init({modules, check_specs}) do
    Enum.each(modules, &Code.ensure_loaded/1)

    case init_checks(modules, check_specs) do
      {:ok, runtimes} ->
        case start_workers(runtimes) do
          {:ok, workers} ->
            {:ok, %{workers: workers}}

          {:error, reason} ->
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:stop, _, state) do
    coverage =
      Enum.reduce(state.workers, empty_coverage(), fn worker, coverage ->
        {check, check_coverage} = TraceWorker.stop(worker)

        coverage
        |> put_in([:checks, check], check_coverage)
        |> merge_coverage(check_coverage)
      end)

    {:stop, :normal, coverage, %{state | workers: []}}
  end

  @impl GenServer
  def handle_cast(:start_observation_window, state) do
    Enum.each(state.workers, &TraceWorker.start_observation_window/1)
    {:noreply, state}
  end

  def handle_cast({:ex_unit_test_started, label}, state) do
    Enum.each(state.workers, &TraceWorker.ex_unit_test_started(&1, label))
    {:noreply, state}
  end

  def handle_cast({:ex_unit_test_finished, label}, state) do
    Enum.each(state.workers, &TraceWorker.ex_unit_test_finished(&1, label))
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_, state) do
    Enum.each(state.workers, &stop_worker/1)
    :ok
  end

  defp init_checks(modules, check_specs) do
    Enum.reduce_while(check_specs, {:ok, [], MapSet.new()}, fn {check, opts},
                                                               {:ok, runtimes, claims} ->
      context = %{claims: claims}

      case check.init(modules, opts, context) do
        {:ok, check_state, plan} ->
          runtime = %{
            module: check,
            state: check_state,
            calls: plan.calls,
            returns: plan.returns,
            process_scope: Map.get(plan, :process_scope, :all),
            trace_scope: Map.get(plan, :trace_scope, :local)
          }

          {:cont, {:ok, [runtime | runtimes], MapSet.union(claims, plan.claims)}}

        {:error, reason} ->
          terminate_pending_checks(runtimes)
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, runtimes, _claims} -> {:ok, Enum.reverse(runtimes)}
      error -> error
    end
  end

  defp start_workers(runtimes), do: start_workers(runtimes, [])

  defp start_workers([], workers), do: {:ok, Enum.reverse(workers)}

  defp start_workers([runtime | remaining], workers) do
    case TraceWorker.start_link(runtime) do
      {:ok, worker} ->
        start_workers(remaining, [worker | workers])

      {:error, reason} ->
        Enum.each(workers, &stop_worker/1)
        terminate_pending_checks(remaining)
        {:error, reason}
    end
  end

  defp stop_worker(worker) do
    if Process.alive?(worker) do
      TraceWorker.stop(worker)
    end

    :ok
  catch
    :exit, _ -> :ok
  end

  defp terminate_pending_checks(runtimes) do
    runtimes
    |> Enum.reverse()
    |> Enum.each(fn runtime -> runtime.module.terminate(runtime.state) end)
  end

  defp empty_coverage do
    %{
      input_classes: [],
      boundaries: [],
      return_alternatives: [],
      compiler_return_alternatives: [],
      compiler_modules: [],
      compiler_warnings: [],
      compiler_calls: %{},
      hits: %{},
      calls: %{},
      return_events: %{},
      unknown: MapSet.new(),
      clauses: [],
      clause_outcomes: %{},
      unmatched_clause_calls: %{},
      arities: [],
      arity_calls: %{},
      structural_modules: [],
      warnings: [],
      checks: %{}
    }
  end

  defp merge_coverage(coverage, check_coverage) do
    Enum.reduce(check_coverage, coverage, fn
      {:unknown, unknown}, merged ->
        Map.update!(merged, :unknown, &MapSet.union(&1, unknown))

      {key, values}, merged
      when key in [
             :input_classes,
             :boundaries,
             :return_alternatives,
             :compiler_return_alternatives,
             :compiler_modules,
             :compiler_warnings,
             :clauses,
             :arities,
             :structural_modules,
             :warnings
           ] ->
        Map.update!(merged, key, &(&1 ++ values))

      {key, counters}, merged
      when key in [
             :hits,
             :calls,
             :compiler_calls,
             :return_events,
             :clause_outcomes,
             :unmatched_clause_calls,
             :arity_calls
           ] ->
        Map.update!(merged, key, fn existing ->
          Map.merge(existing, counters, fn _, left, right -> max(left, right) end)
        end)

      {_key, _value}, merged ->
        merged
    end)
  end
end
