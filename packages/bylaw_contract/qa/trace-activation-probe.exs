Code.prepend_path(System.fetch_env!("BYLAW_OVERHEAD_EBIN"))
Code.require_file("trace-activation-check.exs", __DIR__)

defmodule BylawTraceActivationProbe do
  @moduledoc false
  alias Bylaw.Contract

  @doc false
  @spec run(list(module()), list(tuple()), non_neg_integer(), String.t()) :: map()
  def run(modules, all_mfas, count, mode) do
    selected = Enum.take(all_mfas, count)

    kinds =
      selected |> Enum.with_index() |> Map.new(fn {mfa, index} -> {mfa, kinds(mode, index)} end)

    calls = Enum.filter(selected, &(:call in Map.fetch!(kinds, &1)))
    returns = Enum.filter(selected, &(:return in Map.fetch!(kinds, &1)))
    call_set = MapSet.new(calls)
    return_set = MapSet.new(returns)
    sources = Map.new(modules, &{Atom.to_string(&1), Base.encode16(&1.module_info(:md5))})

    {planning_us, checksum} =
      :timer.tc(fn ->
        call_set
        |> MapSet.union(return_set)
        |> Enum.reduce(0, fn mfa, sum ->
          case {MapSet.member?(call_set, mfa), MapSet.member?(return_set, mfa)} do
            {true, true} -> sum + 3
            {true, false} -> sum + 1
            {false, true} -> sum + 2
          end
        end)
      end)

    true = checksum == length(calls) + 2 * length(returns)
    before_start = memory()
    start_started_us = System.monotonic_time(:microsecond)

    {start_us, {:ok, observer}} =
      :timer.tc(fn ->
        Contract.start(modules,
          checks: [{BylawTraceActivationCheck, calls: calls, returns: returns}]
        )
      end)

    start_finished_us = System.monotonic_time(:microsecond)

    try do
      after_start = memory()
      [worker] = :sys.get_state(observer).workers
      state = :sys.get_state(worker)
      4096 = state.runtime.queue_limit
      session = state.session
      if count == 0, do: nil = session

      if session do
        for module <- modules, {function, arity} <- module.module_info(:exports) do
          mfa = {module, function, arity}
          expected = if Map.has_key?(kinds, mfa), do: :local, else: false
          {:traced, ^expected} = :trace.info(session, mfa, :traced)
        end
      end

      {workload_us, _} =
        :timer.tc(fn ->
          for group <- Enum.chunk_every(selected, 64) do
            for {module, function, 1} <- group, do: :input = apply(module, function, [:input])
            reference = :trace.delivered(session, :all)

            receive do
              {:trace_delivered, :all, ^reference} -> :ok
            after
              2_000 -> raise "trace delivery did not complete"
            end

            %{session: ^session} = :sys.get_state(worker)
            :ok
          end
        end)

      before_stop = memory()
      stop_started_us = System.monotonic_time(:microsecond)
      {stop_us, coverage} = :timer.tc(fn -> Contract.stop(observer) end)
      stop_finished_us = System.monotonic_time(:microsecond)
      after_stop = memory()
      :complete = Map.get(coverage, :status, :complete)
      events = coverage.checks[BylawTraceActivationCheck].events
      caller = self()
      true = Enum.all?(events, fn {_, producer} -> producer == caller end)
      normalized_events = Enum.map(events, &elem(&1, 0))

      expected_events =
        for mfa <- selected, kind <- Map.fetch!(kinds, mfa) do
          case kind do
            :call -> {:call, mfa, [:input]}
            :return -> {:return, mfa, :input}
          end
        end

      ^expected_events = normalized_events

      expected_count =
        case mode do
          "both" -> count * 2
          "mixed" -> count + div(count, 3)
          _ -> count
        end

      ^expected_count = length(events)
      normalized = put_in(coverage.checks[BylawTraceActivationCheck].events, normalized_events)
      {:ok, io} = StringIO.open("")
      {report_us, _} = :timer.tc(fn -> Bylaw.Contract.Report.print(coverage, io, false) end)
      {_, report} = StringIO.contents(io)
      StringIO.close(io)
      ^sources = Map.new(modules, &{Atom.to_string(&1), Base.encode16(&1.module_info(:md5))})
      await_exit(worker, System.monotonic_time(:millisecond) + 2_000)
      [legacy: :default] = :trace.session_info(:all)

      %{
        count: count,
        mode: mode,
        calls: length(calls),
        returns: length(returns),
        events: length(events),
        start_us: start_us,
        stop_us: stop_us,
        start_started_us: start_started_us,
        start_finished_us: start_finished_us,
        stop_started_us: stop_started_us,
        stop_finished_us: stop_finished_us,
        workload_us: workload_us,
        report_us: report_us,
        planning_us: planning_us,
        before_start: before_start,
        after_start: after_start,
        before_stop: before_stop,
        after_stop: after_stop,
        complete: true,
        caller_identity: true,
        exact_patterns: true,
        exact_events: true,
        cleanup: true,
        queue_limit: 4096,
        coverage_sha256: digest(normalized),
        report_sha256: Base.encode16(:crypto.hash(:sha256, report)),
        source_md5_sha256: digest(sources)
      }
    after
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end

  defp kinds("calls", _), do: [:call]
  defp kinds("returns", _), do: [:return]
  defp kinds("both", _), do: [:call, :return]
  defp kinds("mixed", index), do: Enum.at([[:call], [:return], [:call, :return]], rem(index, 3))

  defp await_exit(worker, deadline) do
    cond do
      not Process.alive?(worker) ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "worker did not exit"

      true ->
        Process.sleep(1)
        await_exit(worker, deadline)
    end
  end

  defp memory, do: Map.new(:erlang.memory([:total, :processes, :binary, :code, :ets]))

  defp digest(value),
    do:
      value
      |> :erlang.term_to_binary([:deterministic])
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16()
end

config = System.fetch_env!("BYLAW_TRACE_FIXTURE") |> File.read!() |> JSON.decode!()
modules = Enum.map(config["modules"], &String.to_atom/1)
Enum.each(modules, &Code.ensure_loaded!/1)

mfas =
  for module <- modules,
      function <- 1..config["functions"],
      do: {module, String.to_atom("f#{function}"), 1}

count = System.fetch_env!("BYLAW_TRACE_COUNT") |> String.to_integer()
true = count >= 0 and count <= length(mfas)
mode = System.fetch_env!("BYLAW_TRACE_MODE")

cycles =
  for cycle <- ["first", "repeated"],
      do: BylawTraceActivationProbe.run(modules, mfas, count, mode) |> Map.put(:cycle, cycle)

File.write!(System.fetch_env!("BYLAW_TRACE_OUTPUT"), JSON.encode!(%{cycles: cycles}) <> "\n")
