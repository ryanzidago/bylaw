defmodule Bylaw.Contract.Tracer do
  @moduledoc false
  use GenServer

  alias Bylaw.Contract.Check
  alias Bylaw.Contract.TraceWorker

  @spec start_link(
          modules :: list(module()),
          checks :: list({module(), Check.opts()}),
          max_trace_queue :: pos_integer()
        ) :: GenServer.on_start()
  def start_link(modules, checks, limit \\ 4096),
    do: GenServer.start_link(__MODULE__, {modules, checks, limit})

  @spec stop(tracer :: GenServer.server()) :: map()
  def stop(tracer) do
    tracer
    |> GenServer.call(:stop, :infinity)
    |> Enum.reduce(empty_coverage(), fn {check, check_coverage}, coverage ->
      coverage
      |> put_in([:checks, check], check_coverage)
      |> merge_coverage(check_coverage)
    end)
    |> mark_incomplete()
  end

  defp mark_incomplete(%{incomplete: _} = coverage), do: Map.put(coverage, :status, :incomplete)
  defp mark_incomplete(coverage), do: coverage

  @spec start_observation_window(tracer :: GenServer.server()) :: :ok
  def start_observation_window(tracer), do: GenServer.cast(tracer, :start_observation_window)

  @spec ex_unit_test_started(tracer :: GenServer.server(), label :: term()) :: :ok
  def ex_unit_test_started(tracer, label),
    do: GenServer.cast(tracer, {:ex_unit_test_started, label})

  @spec ex_unit_test_finished(tracer :: GenServer.server(), label :: term()) :: :ok
  def ex_unit_test_finished(tracer, label),
    do: GenServer.cast(tracer, {:ex_unit_test_finished, label})

  @impl GenServer
  def init({modules, check_specs, limit}) do
    Process.flag(:trap_exit, true)
    Enum.each(modules, &Code.ensure_loaded/1)

    case start_workers(modules, check_specs, limit) do
      {:ok, workers} -> {:ok, %{workers: workers}}
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl GenServer
  def handle_call(:stop, _, state) do
    coverage = Enum.map(state.workers, &TraceWorker.stop/1)

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
  def handle_info({:EXIT, _worker, :normal}, state), do: {:noreply, state}

  def handle_info({:EXIT, _worker, reason}, state), do: {:stop, reason, state}

  @impl GenServer
  def terminate(_, state) do
    Enum.each(state.workers, &stop_worker/1)
    :ok
  end

  defp start_workers(modules, check_specs, limit) do
    Enum.reduce_while(check_specs, {:ok, [], MapSet.new()}, fn {check, opts},
                                                               {:ok, workers, claims} ->
      case TraceWorker.start_link(modules, check, opts, claims, limit) do
        {:ok, worker} ->
          claims = MapSet.union(claims, TraceWorker.claims(worker))
          {:cont, {:ok, [worker | workers], claims}}

        {:error, reason} ->
          Enum.each(workers, &stop_worker/1)
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, workers, _claims} -> activate_workers(Enum.reverse(workers))
      error -> error
    end
  end

  defp activate_workers(workers) do
    Enum.reduce_while(workers, {:ok, workers}, fn worker, result ->
      case TraceWorker.activate(worker) do
        :ok ->
          {:cont, result}

        {:error, reason} ->
          Enum.each(Enum.reverse(workers), &stop_worker/1)
          {:halt, {:error, reason}}
      end
    end)
  end

  defp stop_worker(worker) do
    if Process.alive?(worker) do
      GenServer.stop(worker, :normal, :infinity)
    end

    :ok
  catch
    :exit, _ -> :ok
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
      {:incomplete, reasons}, merged ->
        Map.update(merged, :incomplete, reasons, &(&1 ++ reasons))

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
