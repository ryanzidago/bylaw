defmodule Bylaw.Contract.TraceBacklogAcceptanceTest do
  use ExUnit.Case, async: false
  alias Bylaw.Contract
  alias Bylaw.Contract.Check

  defmodule ScopedTypespec do
    @behaviour Check
    @impl Check
    def init(modules, opts, context) do
      {:ok, state, plan} = Check.Typespec.init(modules, opts, context)
      {:ok, state, Map.put(plan, :process_scope, :ex_unit_tests)}
    end

    @impl Check
    defdelegate observe(event, state), to: Check.Typespec
    @impl Check
    defdelegate coverage(state), to: Check.Typespec
    @impl Check
    defdelegate terminate(state), to: Check.Typespec
  end

  setup do
    module = Module.concat(__MODULE__, Fixture)

    directory =
      Path.join(System.tmp_dir!(), "bylaw-backlog-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    source = Path.join(directory, "fixture.ex")

    File.write!(source, """
    defmodule #{inspect(module)} do
      @spec consume(list(integer())) :: {:ok, list(integer())} | {:error, :empty}
      def consume([]), do: {:error, :empty}
      def consume(values), do: {:ok, values}
      @spec hold(list(integer()), pid()) :: {:ok, list(integer())} | {:error, :empty}
      def hold(values, parent) do
        send(parent, {:held, self()})
        receive do :release -> {:ok, values} end
      end
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

    :code.delete(module)
    :code.purge(module)
    Code.prepend_path(directory)
    {:module, ^module} = :code.load_file(module)

    on_exit(fn ->
      :code.delete(module)
      :code.purge(module)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end)

    %{module: module}
  end

  test "Typespec explicitly reports incomplete observation when its trace backlog exceeds the budget",
       %{module: module} do
    coverage = observe(module, [checks: [Check.Typespec], max_trace_queue: 64], :paused, 100)
    assert_incomplete(coverage, Check.Typespec, 64)
  end

  test "FunctionClauses explicitly reports incomplete observation when its trace backlog exceeds the budget",
       %{module: module} do
    coverage =
      observe(module, [checks: [Check.FunctionClauses], max_trace_queue: 64], :paused, 100)

    assert_incomplete(coverage, Check.FunctionClauses, 64)
  end

  test "default checks enforce the declared backlog budget with paused consumers", %{
    module: module
  } do
    coverage = observe(module, [max_trace_queue: 64], :paused, 100)
    assert_incomplete(coverage, Check.Typespec, 64)
    assert_incomplete(coverage, Check.FunctionClauses, 64)
  end

  test "running and delayed consumers preserve exact call and return counts within budget", %{
    module: module
  } do
    for checks <- [
          [Check.Typespec],
          [Check.FunctionClauses],
          [Check.Typespec, Check.FunctionClauses]
        ],
        speed <- [:running, :paused] do
      coverage = observe(module, [checks: checks, max_trace_queue: 4096], speed, 100)
      refute Map.has_key?(coverage, :incomplete)
      mfa = {module, :consume, 1}

      if Check.Typespec in checks do
        assert coverage.calls[mfa] == 100
        assert coverage.return_events[mfa] == 100
      end

      if Check.FunctionClauses in checks, do: assert(coverage.arity_calls[mfa] == 100)
    end
  end

  test "successful budgeted observation preserves target and report equality", %{module: module} do
    running = observe(module, [max_trace_queue: 4096], :running, 100)
    delayed = observe(module, [max_trace_queue: 4096], :paused, 100)
    assert running == delayed
    assert report(running) == report(delayed)
    assert :erlang.binary_to_term(:erlang.term_to_binary(delayed)) == delayed
  end

  test "incomplete observation never reports unassessed targets as actionable misses", %{
    module: module
  } do
    coverage = observe(module, [max_trace_queue: 64], :paused, 100)
    assert coverage.status == :incomplete
    assert Enum.any?(coverage.input_classes)
    assert Enum.any?(coverage.clauses)
    assert %{status: :incomplete, incomplete: reasons} = Contract.summary(coverage)
    assert Enum.any?(reasons)
    output = report(coverage)
    assert output =~ "incomplete"
    refute output =~ "Missed"
    refute output =~ "no test exercises"
  end

  test "repeated successful and incomplete observations release tracing and budget resources", %{
    module: module
  } do
    for _ <- 1..3 do
      complete = observe(module, [max_trace_queue: 4096], :paused, 100)
      refute Map.has_key?(complete, :incomplete)
      incomplete = observe(module, [max_trace_queue: 64], :paused, 100)
      assert incomplete.status == :incomplete
    end
  end

  test "budget exhaustion suppresses returns from already running observed calls", %{
    module: module
  } do
    {:ok, observer} = Contract.start([module], checks: [Check.Typespec], max_trace_queue: 64)
    [worker] = :sys.get_state(observer).workers
    session = :sys.get_state(worker).session
    parent = self()
    held = Task.async(fn -> module.hold([1], parent) end)
    assert_receive {:held, held_pid}, 1000

    try do
      :sys.suspend(worker)
      for _ <- 1..100, do: module.consume([1])
      Process.sleep(30)
      await_exhausted(session)
      queued = Process.info(worker, :message_queue_len)
      send(held_pid, :release)
      assert Task.await(held) == {:ok, [1]}
      Process.sleep(10)
      assert Process.info(worker, :message_queue_len) == queued
      :sys.resume(worker)
      assert_incomplete(Contract.stop(observer), Check.Typespec, 64)
    after
      if Process.alive?(held.pid), do: send(held.pid, :release)
      if Process.alive?(worker), do: :sys.resume(worker)
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end

  test "an exhausted session cannot be reactivated by later test process discovery", %{
    module: module
  } do
    {:ok, observer} = Contract.start([module], checks: [ScopedTypespec], max_trace_queue: 64)
    [worker] = :sys.get_state(observer).workers
    session = :sys.get_state(worker).session
    label = {__MODULE__, :first}
    producer = labeled_producer(module, label)
    Contract.Tracer.start_observation_window(observer)
    Contract.Tracer.ex_unit_test_started(observer, label)
    await_traced(session, producer)

    try do
      :sys.suspend(worker)
      send(producer, :run)
      assert_receive {:produced, ^producer}, 1000
      await_exhausted(session)
      :sys.resume(worker)
      :sys.get_state(worker)
      next_label = {__MODULE__, :second}
      next_producer = labeled_producer(module, next_label)
      Contract.Tracer.ex_unit_test_started(observer, next_label)
      Process.sleep(20)
      send(next_producer, :run)
      assert_receive {:produced, ^next_producer}, 1000
      assert_raise ArgumentError, fn -> :trace.info(session, next_producer, :flags) end
      send(next_producer, :stop)
      assert_incomplete(Contract.stop(observer), ScopedTypespec, 64)
    after
      send(producer, :stop)
      if Process.alive?(worker), do: :sys.resume(worker)
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end

  defp labeled_producer(module, label) do
    parent = self()

    spawn_link(fn ->
      :proc_lib.set_label(label)
      send(parent, {:ready, self()})

      receive do
        :run ->
          for _ <- 1..100, do: module.consume([1])
          send(parent, {:produced, self()})
      end

      receive do
        :stop -> :ok
      end
    end)
    |> then(fn pid ->
      assert_receive {:ready, ^pid}, 1000
      on_exit(fn -> if Process.alive?(pid), do: Process.exit(pid, :kill) end)
      pid
    end)
  end

  defp await_traced(session, producer, attempts \\ 100)
  defp await_traced(_session, _producer, 0), do: flunk("producer was not traced")

  defp await_traced(session, producer, attempts) do
    case :trace.info(session, producer, :flags) do
      {:flags, flags} ->
        if :call in flags do
          :ok
        else
          Process.sleep(5)
          await_traced(session, producer, attempts - 1)
        end
    end
  end

  defp await_exhausted(session, attempts \\ 200)

  defp await_exhausted(_session, 0),
    do: flunk("trace session did not stop after budget exhaustion")

  defp await_exhausted(session, attempts) do
    :trace.info(session, self(), :flags)
    Process.sleep(5)
    await_exhausted(session, attempts - 1)
  catch
    :error, :badarg -> :ok
  end

  test "default budget preserves the bounded thousand-call return workload", %{module: module} do
    coverage = observe(module, [], :paused, 1000)
    refute Map.has_key?(coverage, :incomplete)
    assert coverage.calls[{module, :consume, 1}] == 1000
    assert coverage.return_events[{module, :consume, 1}] == 1000
    assert coverage.arity_calls[{module, :consume, 1}] == 1000
  end

  defp assert_incomplete(coverage, check, limit) do
    assert coverage.status == :incomplete

    assert Enum.any?(coverage.incomplete, fn reason ->
             reason.check == check and reason.reason == :trace_queue_limit and
               reason.limit == limit and reason.observed > limit
           end)
  end

  defp observe(module, options, speed, calls) do
    {:ok, observer} = Contract.start([module], options)
    workers = :sys.get_state(observer).workers
    sessions = Enum.map(workers, &:sys.get_state(&1).session)
    assert Enum.all?(sessions, &(not is_nil(&1)))

    linked =
      for worker <- workers,
          {:links, pids} = Process.info(worker, :links),
          pid <- pids,
          pid != observer,
          do: pid

    try do
      if speed == :paused, do: Enum.each(workers, &:sys.suspend/1)
      payload = Enum.to_list(1..256)
      for _ <- 1..calls, do: assert(module.consume(payload) == {:ok, payload})
      Process.sleep(30)

      if options[:max_trace_queue] == 64 do
        Enum.each(sessions, &await_exhausted/1)
        queued = Enum.map(workers, &Process.info(&1, :message_queue_len))
        task = Task.async(fn -> for _ <- 1..100, do: module.consume(payload) end)
        Task.await(task)
        Process.sleep(10)
        assert Enum.map(workers, &Process.info(&1, :message_queue_len)) == queued
      end

      if speed == :paused, do: Enum.each(workers, &:sys.resume/1)
      coverage = Contract.stop(observer)
      assert Enum.all?(workers ++ linked, &(not Process.alive?(&1)))

      for session <- sessions do
        assert_raise ArgumentError, fn -> :trace.info(session, {module, :consume, 1}, :traced) end
      end

      coverage
    after
      for worker <- workers, Process.alive?(worker), do: :sys.resume(worker)
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end

  defp report(coverage) do
    {:ok, device} = StringIO.open("")

    try do
      :ok = Contract.print_report(coverage, device, colors: false)
      {_, output} = StringIO.contents(device)
      output
    after
      StringIO.close(device)
    end
  end
end
