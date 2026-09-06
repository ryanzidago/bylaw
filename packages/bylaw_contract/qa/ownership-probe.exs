# QA-only use of private worker state. Run in its own VM, never load into a caller app.
Code.require_file("ownership-adapter.exs", __DIR__)
[mode, scenario, output, idle_count, profiling] = System.argv()
true = mode in ["scan", "explicit", "all"]
true = scenario in ["immediate", "settled", "matched", "failure", "timeout", "exhausted"]
:ets.new(:ownership_oracle, [:named_table, :public, :set])
:ets.new(:ownership_roots, [:named_table, :public, :set])
:ets.new(:ownership_metrics, [:named_table, :public, :duplicate_bag])
:persistent_term.put(:ownership_options, %{mode: mode, scenario: scenario})

defmodule BylawOwnershipTarget do
  @doc false
  @spec hit(atom(), non_neg_integer()) :: :ok
  def hit(kind, depth) do
    :ets.update_counter(
      :ownership_oracle,
      {self(), kind, depth},
      {2, 1},
      {{self(), kind, depth}, 0}
    )

    if depth > 0, do: hit(kind, depth - 1)
    :ok
  end
end

defmodule BylawOwnershipCheck do
  @behaviour Bylaw.Contract.Check
  @impl Bylaw.Contract.Check
  def init(_modules, options, _context) do
    mfas = MapSet.new([{BylawOwnershipTarget, :hit, 2}])
    {:ok, [], %{calls: mfas, returns: mfas, claims: MapSet.new(), process_scope: options[:scope]}}
  end

  @impl Bylaw.Contract.Check
  def observe(_event, state), do: state
  @impl Bylaw.Contract.Check
  def observe(event, caller, state), do: [{caller, event} | state]
  @impl Bylaw.Contract.Check
  def coverage(state), do: %{events: Enum.reverse(state)}
  @impl Bylaw.Contract.Check
  def terminate(_state), do: :ok
end

defmodule BylawOwnershipProbe do
  @doc false
  @spec measure_scan((-> term())) :: term()
  def measure_scan(function) do
    start = System.monotonic_time(:microsecond)

    try do
      function.()
    after
      :ets.insert(:ownership_metrics, {:scan, System.monotonic_time(:microsecond) - start})
    end
  end

  @doc false
  @spec await((-> boolean()), non_neg_integer()) :: :ok
  def await(function, remaining \\ 2000)
  def await(_function, 0), do: raise("bounded ownership probe wait expired")

  def await(function, remaining) do
    if function.(),
      do: :ok,
      else:
        (
          Process.sleep(1)
          await(function, remaining - 1)
        )
  end

  @doc false
  @spec sample(pid(), map()) :: :ok
  def sample(worker, values \\ %{samples: 0, queue_peak: 0, worker_peak_bytes: 0}) do
    values =
      case Process.info(worker, [:message_queue_len, :memory]) do
        nil ->
          values

        info ->
          %{
            samples: values.samples + 1,
            queue_peak: max(values.queue_peak, info[:message_queue_len]),
            worker_peak_bytes: max(values.worker_peak_bytes, info[:memory])
          }
      end

    receive do
      {:finish, recipient} ->
        send(recipient, {:ownership_samples, values})
        :ok
    after
      5 -> sample(worker, values)
    end
  end

  @doc false
  @spec register(map()) :: :ok
  def register(context) do
    %{mode: mode, scenario: scenario} = :persistent_term.get(:ownership_options)
    :ets.insert(:ownership_roots, {self(), context.test, context.lane})
    %{session: session} = :persistent_term.get(:ownership_runtime)

    cond do
      mode == "explicit" ->
        :ok = BylawOwnershipAdapter.register(context.test_pid)

      mode == "scan" and scenario in ["settled", "matched"] ->
        await(fn -> match?({:flags, [:call]}, :trace.info(session, self(), :flags)) end)

      true ->
        :ok
    end

    :ok
  end
end

if profiling == "diagnostic" do
  path = Path.expand("../lib/bylaw/contract/trace_worker.ex", __DIR__)
  ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

  ast =
    Macro.prewalk(ast, fn
      {:defp, meta, [{:trace_labeled_test_processes, _, _} = head, body]} ->
        wrapped = if Keyword.keys(body) == [:do], do: body[:do], else: {:try, [], [body]}

        {:defp, meta,
         [head, [do: quote(do: BylawOwnershipProbe.measure_scan(fn -> unquote(wrapped) end))]]}

      other ->
        other
    end)

  options = Code.compiler_options()

  try do
    Code.compiler_options(ignore_module_conflict: true)
    Code.compile_quoted(ast, path)
  after
    Code.compiler_options(options)
  end
end

defmodule BylawOwnershipFormatter do
  use GenServer
  @impl GenServer
  def init(_options) do
    %{mode: mode} = :persistent_term.get(:ownership_options)
    scope = if mode == "all", do: :all, else: :ex_unit_tests

    {:ok, tracer} =
      Bylaw.Contract.start([BylawOwnershipTarget],
        checks: [{BylawOwnershipCheck, scope: scope}]
      )

    Process.unlink(tracer)
    [worker] = :sys.get_state(tracer).workers
    session = :sys.get_state(worker).session
    budget_pid = :sys.get_state(worker).budget.pid
    sampler = spawn(fn -> BylawOwnershipProbe.sample(worker) end)

    adapter =
      if mode == "explicit" do
        {:ok, pid} = BylawOwnershipAdapter.start_link(worker)
        Process.unlink(pid)
        pid
      end

    :persistent_term.put(:ownership_runtime, %{
      tracer: tracer,
      worker: worker,
      session: session,
      adapter: adapter,
      budget_pid: budget_pid,
      sampler: sampler
    })

    Bylaw.Contract.Tracer.start_observation_window(tracer)
    BylawOwnershipProbe.await(fn -> :sys.get_state(worker).patterns_configured? end)
    {:ok, %{tracer: tracer, tests: []}}
  end

  @impl GenServer
  def handle_cast({:test_started, test}, state) do
    Bylaw.Contract.Tracer.ex_unit_test_started(state.tracer, {test.case, test.name})
    {:noreply, state}
  end

  def handle_cast({:test_finished, test}, state) do
    Bylaw.Contract.Tracer.ex_unit_test_finished(state.tracer, {test.case, test.name})

    row = %{
      name: to_string(test.name),
      lane: test.parameters.lane,
      state: if(test.state, do: "failed", else: "passed"),
      failure: inspect(test.state)
    }

    {:noreply, %{state | tests: [row | state.tests]}}
  end

  def handle_cast({:suite_finished, _timings}, state) do
    :persistent_term.put(:ownership_tests, state.tests)
    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end

defmodule BylawOwnershipChild do
  use GenServer
  @impl GenServer
  def init(_argument) do
    BylawOwnershipTarget.hit(:supervised, 0)
    {:ok, nil}
  end

  @doc false
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(arg), do: GenServer.start_link(__MODULE__, arg)
end

idle =
  for _ <- List.duplicate(:idle, String.to_integer(idle_count)),
      do: spawn(fn -> receive do: (:stop -> :ok) end)

preexisting =
  spawn(fn ->
    loop = fn loop ->
      receive do
        {:call, caller} ->
          BylawOwnershipTarget.hit(:preexisting, 0)
          send(caller, :preexisting_done)
          loop.(loop)

        :stop ->
          :ok
      end
    end

    loop.(loop)
  end)

:persistent_term.put(:ownership_preexisting, preexisting)

ExUnit.start(
  autorun: false,
  seed: 922_331,
  max_cases: 4,
  formatters: [ExUnit.CLIFormatter, BylawOwnershipFormatter]
)

defmodule BylawOwnershipFixture do
  use ExUnit.Case, async: true, parameterize: for(lane <- 1..4, do: %{lane: lane})

  setup_all do
    BylawOwnershipTarget.hit(:setup_all, 0)
    :ok
  end

  setup do
    unless :persistent_term.get(:ownership_options).scenario == "matched",
      do: BylawOwnershipTarget.hit(:before_registration, 0)

    :ok
  end

  setup context do
    BylawOwnershipProbe.register(context)
    BylawOwnershipTarget.hit(:setup, 0)
    on_exit(fn -> BylawOwnershipTarget.hit(:on_exit, 0) end)
    :ok
  end

  test "root body and recursion", context do
    for _ <- 1..10 do
      BylawOwnershipTarget.hit(:body, 0)
      Process.sleep(2)
    end

    BylawOwnershipTarget.hit(:recursive, 3)
    %{scenario: scenario} = :persistent_term.get(:ownership_options)
    if context.lane == 1 and scenario == "failure", do: flunk("retained fixture failure")

    if context.lane == 1 and scenario == "timeout",
      do: receive(do: (:never -> :ok), after: (60_000 -> :ok))

    Process.sleep(30)
  end

  test "nested tasks retain their own caller identities" do
    BylawOwnershipTarget.hit(:body, 0)

    task =
      Task.async(fn ->
        BylawOwnershipTarget.hit(:task, 0)
        Task.async(fn -> BylawOwnershipTarget.hit(:nested_task, 0) end) |> Task.await()
      end)

    assert Task.await(task) == :ok
    Process.sleep(30)
  end

  test "supervised ordinary and pre-existing children keep distinct callers" do
    BylawOwnershipTarget.hit(:body, 0)
    start_supervised!(BylawOwnershipChild)
    parent = self()

    spawn(fn ->
      BylawOwnershipTarget.hit(:spawn, 0)
      send(parent, :spawn_done)
    end)

    assert_receive :spawn_done
    send(:persistent_term.get(:ownership_preexisting), {:call, self()})
    assert_receive :preexisting_done
    Process.sleep(30)
  end
end

if scenario == "timeout", do: ExUnit.configure(timeout: 100)
suite_started = System.monotonic_time(:microsecond)
result = ExUnit.run()
suite_us = System.monotonic_time(:microsecond) - suite_started
runtime = :persistent_term.get(:ownership_runtime)

registration =
  if runtime.adapter do
    BylawOwnershipProbe.await(fn -> GenServer.call(runtime.adapter, :snapshot).retained == 0 end)
    GenServer.call(runtime.adapter, :snapshot)
  else
    %{
      count: 0,
      retained: MapSet.size(:sys.get_state(runtime.worker).traced_test_processes),
      times_us: []
    }
  end

rejected =
  if scenario == "exhausted" do
    :ok = BylawOwnershipAdapter.register(self())
    budget = :sys.get_state(runtime.worker).budget
    :sys.suspend(runtime.worker)
    for _ <- 1..5000, do: BylawOwnershipTarget.hit(:overflow, 0)
    BylawOwnershipProbe.await(fn -> Bylaw.Contract.TraceQueueBudget.check(budget) > 0 end)
    :sys.resume(runtime.worker)
    {:error, :incomplete} == BylawOwnershipAdapter.register(self())
  end

retained_worker_pids = MapSet.size(:sys.get_state(runtime.worker).traced_test_processes)
send(runtime.sampler, {:finish, self()})

samples =
  receive do
    {:ownership_samples, values} -> values
  after
    2000 -> raise("missing worker sample result")
  end

coverage = Bylaw.Contract.stop(runtime.tracer)
if runtime.adapter, do: BylawOwnershipProbe.await(fn -> not Process.alive?(runtime.adapter) end)
Enum.each(idle, &send(&1, :stop))
send(preexisting, :stop)
BylawOwnershipProbe.await(fn -> Enum.all?([preexisting | idle], &(not Process.alive?(&1))) end)

oracle = Map.new(:ets.tab2list(:ownership_oracle))
roots = MapSet.new(:ets.tab2list(:ownership_roots), &elem(&1, 0))
events = coverage.checks[BylawOwnershipCheck].events

calls =
  Enum.reduce(events, %{}, fn
    {pid, {:call, _, [kind, depth]}}, acc -> Map.update(acc, {pid, kind, depth}, 1, &(&1 + 1))
    _, acc -> acc
  end)

returns =
  Enum.reduce(events, %{}, fn
    {pid, {:return, _, :ok}}, acc -> Map.update(acc, pid, 1, &(&1 + 1))
    _, acc -> acc
  end)

by_pid = fn counts ->
  Enum.reduce(counts, %{}, fn {{pid, _, _}, n}, acc -> Map.update(acc, pid, n, &(&1 + n)) end)
end

promised = fn counts ->
  Map.filter(counts, fn {{pid, kind, _}, _} ->
    MapSet.member?(roots, pid) and kind in [:setup, :body, :recursive]
  end)
end

encode_counts = fn counts ->
  Enum.map(counts, fn {{pid, kind, depth}, n} ->
    %{pid: inspect(pid), kind: kind, depth: depth, count: n}
  end)
end

observed_by_kind =
  Enum.reduce(calls, %{}, fn {{_, kind, _}, n}, acc -> Map.update(acc, kind, n, &(&1 + n)) end)

clean =
  not Process.alive?(runtime.sampler) and not Process.alive?(runtime.budget_pid) and
    not Process.alive?(runtime.tracer) and not Process.alive?(runtime.worker) and
    (is_nil(runtime.adapter) or not Process.alive?(runtime.adapter)) and
    Enum.all?(:trace.session_info(:all), &(&1 == {:legacy, :default}))

scans = for {:scan, us} <- :ets.tab2list(:ownership_metrics), do: us

capture = %{
  mode: mode,
  scenario: scenario,
  idle_count: String.to_integer(idle_count),
  profiling: profiling,
  tests: :persistent_term.get(:ownership_tests),
  native_result: result,
  suite_us: suite_us,
  root_count: MapSet.size(roots),
  oracle_calls: Enum.sum(Map.values(oracle)),
  oracle: encode_counts.(oracle),
  observed: encode_counts.(calls),
  roots: Enum.map(roots, &inspect/1),
  observed_by_kind: observed_by_kind,
  promised_expected_calls: Enum.sum(Map.values(promised.(oracle))),
  promised_calls_exact: promised.(oracle) == promised.(calls),
  all_calls_exact: oracle == calls,
  caller_returns_exact: by_pid.(calls) == returns,
  incomplete: Map.has_key?(coverage, :incomplete),
  incomplete_reasons: inspect(Map.get(coverage, :incomplete, [])),
  registration: registration,
  retained_worker_pids: retained_worker_pids,
  rejected_after_exhaustion: rejected,
  sampling: samples,
  scan_count: length(scans),
  scan_us: Enum.sum(scans),
  cleanup: %{clean: clean, sessions: inspect(:trace.session_info(:all))}
}

File.write!(output, JSON.encode!(capture))
if result.failures > 0, do: System.halt(1)
if not clean, do: System.halt(2)
