# elixir -pa EBIN qa/trace-backlog-budget.exs MODE SPEED LIMIT OUTPUT
# LIMIT=0 is the unchanged-library control. Run under memory-watchdog.py.
defmodule Bylaw.Contract.QA.TraceBacklogBudget do
  alias Bylaw.Contract
  alias Bylaw.Contract.Check

  @doc false
  @spec run(arguments :: list(String.t())) :: :ok
  def run([mode, speed, limit, output]) do
    limit = String.to_integer(limit)
    true = limit in [0, 64, 4096]
    true = speed in ["running", "paused", "slow10"]

    checks =
      case mode do
        "typespec" -> [Check.Typespec]
        "structural" -> [Check.FunctionClauses]
        "default" -> [Check.Typespec, Check.FunctionClauses]
      end

    options = [checks: checks]
    options = if limit == 0, do: options, else: Keyword.put(options, :max_trace_queue, limit)
    directory = output <> ".fixture"
    module = Module.concat(__MODULE__, Fixture)
    File.mkdir_p!(directory)
    source = Path.join(directory, "fixture.ex")

    File.write!(source, """
    defmodule #{inspect(module)} do
      @spec consume(list(integer())) :: {:ok, list(integer())} | {:error, :empty}
      def consume([]), do: {:error, :empty}
      def consume(values), do: {:ok, values}
    end
    """)

    compiler_options = Code.compiler_options()

    try do
      Code.compiler_options(debug_info: true)

      {:ok, _, _} =
        Kernel.ParallelCompiler.compile_to_path([source], directory, return_diagnostics: true)
    after
      Code.compiler_options(compiler_options)
    end

    Code.prepend_path(directory)

    try do
      cycles =
        for cycle <- 1..3 do
          result = observe(module, options, checks, speed, limit, directory, cycle)
          :erlang.garbage_collect()
          Process.sleep(40)
          snapshot("cleanup_#{cycle}", [])
          result
        end

      File.write!(
        output,
        :erlang.term_to_binary(%{mode: mode, speed: speed, limit: limit, cycles: cycles})
      )
    after
      :code.delete(module)
      :code.purge(module)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end
  end

  defp observe(module, options, checks, speed, limit, directory, cycle) do
    {:ok, observer} = Contract.start([module], options)
    workers = :sys.get_state(observer).workers
    true = Enum.all?(workers, &(not is_nil(:sys.get_state(&1).session)))
    controller = controller(workers, speed)

    try do
      snapshot("started_#{cycle}", workers)
      payload = Enum.to_list(1..2048)

      {observation_us, :ok} =
        :timer.tc(fn ->
          Enum.each(1..1000, fn _ -> {:ok, ^payload} = module.consume(payload) end)
        end)

      Process.sleep(30)
      snapshot("observed_#{cycle}", workers)
      stop_controller(controller)
      {stop_us, coverage} = :timer.tc(fn -> Contract.stop(observer) end)
      true = Enum.all?(workers, &(not Process.alive?(&1)))
      status = Map.get(coverage, :status, :complete)
      if limit in [0, 4096], do: true = status == :complete
      if limit == 64 and speed == "paused", do: true = status == :incomplete

      if status == :complete do
        mfa = {module, :consume, 1}

        if Check.Typespec in checks do
          1000 = coverage.calls[mfa]
          1000 = coverage.return_events[mfa]
        end

        if Check.FunctionClauses in checks, do: 1000 = coverage.arity_calls[mfa]
      else
        true =
          Enum.all?(
            coverage.incomplete,
            &(&1.limit == limit and &1.observed > limit and &1.reason == :trace_queue_limit)
          )

        %{status: :incomplete} = Contract.summary(coverage)
      end

      {:ok, io} = StringIO.open("")
      :ok = Contract.print_report(coverage, io)
      {_, report} = StringIO.contents(io)
      StringIO.close(io)

      if status == :incomplete do
        true = String.contains?(report, "incomplete")
        false = String.contains?(report, "Missed")
      end

      true = :erlang.binary_to_term(:erlang.term_to_binary(coverage)) == coverage
      snapshot("stopped_#{cycle}", [])

      %{
        status: status,
        incomplete: Map.get(coverage, :incomplete, []),
        coverage_hash: hash(normalize(coverage, directory)),
        report_hash: hash(String.replace(report, directory, "<fixture>")),
        observation_us: observation_us,
        stop_us: stop_us
      }
    after
      stop_controller(controller)
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end

  defp controller(_workers, "running"), do: nil

  defp controller(workers, speed) do
    parent = self()

    pid =
      spawn_link(fn ->
        Enum.each(workers, &:sys.suspend/1)
        send(parent, {:ready, self()})
        control(workers, speed)
      end)

    receive do
      {:ready, ^pid} -> pid
    end
  end

  defp control(workers, "paused") do
    receive do
      :stop -> Enum.each(workers, &:sys.resume/1)
    end
  end

  defp control(workers, "slow10") do
    receive do
      :stop -> Enum.each(workers, &:sys.resume/1)
    after
      10 ->
        Enum.each(workers, &:sys.resume/1)

        receive do
          :stop -> :ok
        after
          2 ->
            Enum.each(workers, &:sys.suspend/1)
            control(workers, "slow10")
        end
    end
  end

  defp stop_controller(nil), do: :ok

  defp stop_controller(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)

    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    end
  end

  defp hash(term),
    do: :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic])) |> Base.encode16()

  defp normalize(term, directory) when is_map(term),
    do:
      Map.new(:maps.to_list(term), fn {k, v} ->
        {normalize(k, directory), normalize(v, directory)}
      end)

  defp normalize(term, directory) when is_list(term),
    do: Enum.map(term, &normalize(&1, directory))

  defp normalize(term, directory) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.map(&normalize(&1, directory)) |> List.to_tuple()

  defp normalize(term, directory) when is_binary(term),
    do: String.replace(term, directory, "<fixture>")

  defp normalize(term, _directory), do: term

  defp snapshot(phase, workers) do
    memory = Map.new(:erlang.memory())

    IO.puts(
      JSON.encode!(%{
        phase: phase,
        wall_us: System.system_time(:microsecond),
        beam: memory,
        workers: Enum.map(workers, &Map.new(Process.info(&1, [:memory, :message_queue_len])))
      })
    )

    if memory.total > 384 * 1024 * 1024, do: System.halt(86)
  end
end

Bylaw.Contract.QA.TraceBacklogBudget.run(System.argv())
