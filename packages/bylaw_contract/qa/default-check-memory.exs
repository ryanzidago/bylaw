# elixir -pa EBIN qa/default-check-memory.exs MODE SPEED CALLS PAYLOAD OUTPUT
# Only bounded synthetic fixtures; run under memory-watchdog.py.
defmodule Bylaw.Contract.QA.DefaultCheckMemory do
  alias Bylaw.Contract.Check

  @doc false
  @spec run(arguments :: list(String.t())) :: :ok
  def run([mode, speed, calls, payload_size, output]) do
    calls = String.to_integer(calls)
    payload_size = String.to_integer(payload_size)
    true = calls in 1..1000 and payload_size in 0..2048
    true = speed in ["running", "slow", "paused"]

    checks =
      case mode do
        "baseline" -> []
        "typespec" -> [Check.Typespec]
        "structural" -> [Check.FunctionClauses]
        "default" -> [Check.Typespec, Check.FunctionClauses]
      end

    directory = output <> ".fixture"
    File.mkdir_p!(directory)
    module = Bylaw.Contract.QA.GenericPayload
    watchdog = spawn(fn -> watch_memory() end)
    initial = snapshot("before_fixture", [])

    try do
      source = Path.join(directory, "payload.ex")

      File.write!(source, """
      defmodule #{inspect(module)} do
        @spec consume(list(integer())) :: non_neg_integer()
        def consume(values), do: length(values)
      end
      """)

      options = Code.compiler_options()

      try do
        Code.compiler_options(debug_info: true)

        {:ok, _, _} =
          Kernel.ParallelCompiler.compile_to_path([source], directory, return_diagnostics: true)
      after
        Code.compiler_options(options)
      end

      Code.prepend_path(directory)
      loaded = snapshot("fixture_loaded", [])
      started = System.monotonic_time(:microsecond)
      observer = if Enum.any?(checks), do: elem(Bylaw.Contract.start([module], checks: checks), 1)
      workers = if observer, do: :sys.get_state(observer).workers, else: []
      sessions = Enum.map(workers, &:sys.get_state(&1).session)
      initialized = snapshot("observer_started", workers)
      init_us = System.monotonic_time(:microsecond) - started
      payload = Enum.to_list(1..payload_size//1)
      true = length(payload) == payload_size

      coverage =
        try do
          if speed == "paused", do: Enum.each(workers, &:sys.suspend/1)

          batches =
            if speed == "slow",
              do: Enum.to_list(50..calls//50) ++ [calls],
              else: [100, 500, calls]

          checkpoints = batches |> Enum.filter(&(&1 <= calls)) |> Enum.uniq() |> Enum.sort()

          Enum.reduce(checkpoints, 0, fn total, previous ->
            if speed == "slow", do: Enum.each(workers, &:sys.suspend/1)
            for _ <- 1..(total - previous), do: apply(module, :consume, [payload])
            delivery_barrier(sessions)
            snapshot("observed_#{total}", workers)

            if speed == "slow" do
              Process.sleep(5)
              Enum.each(workers, &:sys.resume/1)
              Process.sleep(2)
            end

            total
          end)

          if speed == "paused", do: Enum.each(workers, &:sys.resume/1)
          stop_started = System.monotonic_time(:microsecond)
          coverage = if observer, do: Bylaw.Contract.stop(observer), else: nil
          stop_us = System.monotonic_time(:microsecond) - stop_started
          snapshot("stopped", [])
          {coverage, stop_us}
        after
          for worker <- workers, Process.alive?(worker), do: :sys.resume(worker)
          if observer && Process.alive?(observer), do: Bylaw.Contract.stop(observer)
        end

      {coverage, stop_us} = coverage

      if coverage do
        mfa = {module, :consume, 1}
        if Check.Typespec in checks, do: true = coverage.calls[mfa] == calls
        if Check.FunctionClauses in checks, do: true = coverage.arity_calls[mfa] == calls
      end

      summary = if coverage, do: Bylaw.Contract.summary(coverage), else: %{}
      snapshot("summarized", [])
      encoded = :erlang.term_to_binary(coverage, [:deterministic])
      snapshot("encoded", [])

      result = %{
        status: :complete,
        mode: mode,
        speed: speed,
        calls: calls,
        payload: payload_size,
        elixir: System.version(),
        otp: System.otp_release(),
        init_us: init_us,
        stop_us: stop_us,
        initial: initial,
        loaded: loaded,
        initialized: initialized,
        summary: summary,
        encoded_bytes: byte_size(encoded),
        coverage: coverage
      }

      File.write!(output, :erlang.term_to_binary(result, [:compressed]))

      emit(%{
        status: :complete,
        output: output,
        init_us: init_us,
        stop_us: stop_us,
        encoded_bytes: byte_size(encoded)
      })
    after
      send(watchdog, :stop)
      :code.purge(module)
      :code.delete(module)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end
  end

  defp delivery_barrier(sessions) do
    for session <- sessions do
      reference = :trace.delivered(session, :all)

      receive do
        {:trace_delivered, :all, ^reference} -> :ok
      after
        2000 -> raise "trace delivery timed out"
      end
    end
  end

  defp snapshot(phase, workers) do
    data = %{
      phase: phase,
      wall_us: System.system_time(:microsecond),
      beam: Map.new(:erlang.memory()),
      workers:
        Enum.map(workers, fn worker ->
          Map.new(Process.info(worker, [:memory, :message_queue_len]))
        end)
    }

    emit(data)
    data
  end

  defp emit(data), do: IO.puts(JSON.encode!(data))

  defp watch_memory do
    if :erlang.memory(:total) > 384 * 1024 * 1024 do
      emit(%{status: :incomplete_beam_budget})
      System.halt(86)
    end

    receive do
      :stop -> :ok
    after
      20 -> watch_memory()
    end
  end
end

Bylaw.Contract.QA.DefaultCheckMemory.run(System.argv())
