check_path = Path.expand("../qa/trace-activation-check.exs", __DIR__)
if File.exists?(check_path), do: Code.require_file(check_path)

defmodule Bylaw.Contract.TraceActivationProbeTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.StructuralExample, as: Fixture

  @return_only [{:_, [], [{:return_trace}, {:message, false}]}]

  test "activation probe preserves selected calls returns and local private functions" do
    check = check()
    private = {Fixture, :private_classify, 1}
    calls = [{Fixture, :classify, 1}, private, {Fixture, :optional, 1}]

    {:ok, observer} =
      Contract.start([Fixture], checks: [{check, calls: calls, returns: [private]}])

    on_exit(fn -> stop_if_alive(observer) end)
    session = worker_state(observer).session

    for mfa <- calls, do: assert(:trace.info(session, mfa, :traced) == {:traced, :local})

    for mfa <- [
          {Fixture, :guarded_only, 1},
          {Fixture, :through_private, 1},
          {Fixture, :optional, 2}
        ] do
      assert :trace.info(session, mfa, :traced) == {:traced, false}
    end

    assert Fixture.classify(7) == :positive_integer
    assert Fixture.through_private(:private_exact) == :private_exact
    assert Fixture.optional(:left) == {:left, :default}
    assert Fixture.guarded_only(1) == :positive
    coverage = Contract.stop(observer)
    refute Map.has_key?(coverage, :incomplete)

    assert coverage.checks[check].events == [
             {{:call, {Fixture, :classify, 1}, [7]}, self()},
             {{:call, private, [:private_exact]}, self()},
             {{:return, private, :private_exact}, self()},
             {{:call, {Fixture, :optional, 1}, [:left]}, self()}
           ]
  end

  test "activation probe preserves caller identities across independent trace sessions" do
    check = check()
    mfa = {Fixture, :classify, 1}
    options = [checks: [{check, calls: [mfa], returns: [mfa]}]]
    {:ok, first} = Contract.start([Fixture], options)
    {:ok, second} = Contract.start([Fixture], options)
    on_exit(fn -> stop_if_alive(first) end)
    on_exit(fn -> stop_if_alive(second) end)
    refute worker_state(first).session == worker_state(second).session
    task = Task.async(fn -> Fixture.classify(:child) end)
    assert Task.await(task) == :atom
    initial = Contract.stop(first)
    assert Fixture.classify(:exact) == :exact
    remaining = Contract.stop(second)

    assert initial.checks[check].events == [
             {{:call, mfa, [:child]}, task.pid},
             {{:return, mfa, :atom}, task.pid}
           ]

    assert remaining.checks[check].events ==
             initial.checks[check].events ++
               [{{:call, mfa, [:exact]}, self()}, {{:return, mfa, :exact}, self()}]

    refute Map.has_key?(initial, :incomplete)
    refute Map.has_key?(remaining, :incomplete)
  end

  test "activation probe preserves return-only patterns while retiring completed calls" do
    check = check()
    mfa = {Fixture, :classify, 1}

    {:ok, observer} =
      Contract.start([Fixture],
        checks: [{check, calls: [mfa], returns: [mfa], retire_calls: true}]
      )

    on_exit(fn -> stop_if_alive(observer) end)
    assert Fixture.classify(1) == :positive_integer
    flush(observer)
    session = worker_state(observer).session
    assert :trace.info(session, mfa, :match_spec) == {:match_spec, @return_only}
    assert Fixture.classify(:exact) == :exact
    coverage = Contract.stop(observer)

    assert coverage.checks[check].events == [
             {{:call, mfa, [1]}, self()},
             {{:return, mfa, :positive_integer}, self()},
             {{:return, mfa, :exact}, self()}
           ]

    {:ok, returns} = Contract.start([Fixture], checks: [{check, returns: [mfa]}])
    on_exit(fn -> stop_if_alive(returns) end)

    assert :trace.info(worker_state(returns).session, mfa, :match_spec) ==
             {:match_spec, @return_only}

    assert Fixture.classify(:exact) == :exact
    assert Contract.stop(returns).checks[check].events == [{{:return, mfa, :exact}, self()}]
  end

  test "activation probe cleans failed starts without disturbing an existing observer or queue guard" do
    check = check()
    mfa = {Fixture, :classify, 1}
    {:ok, existing} = Contract.start([Fixture], checks: [{check, calls: [mfa]}])
    on_exit(fn -> stop_if_alive(existing) end)
    sessions = :trace.session_info(:all)
    assert worker_state(existing).runtime.queue_limit == 4096
    previous = Process.flag(:trap_exit, true)

    try do
      assert {:error, reason} =
               Contract.start([Fixture],
                 checks: [{check, calls: [mfa], process_scope: :invalid, notify: self()}]
               )

      assert reason =~ "could not configure"
      assert_receive {:trace_activation_terminated, owner}
      refute Process.alive?(owner)
      assert :trace.session_info(:all) == sessions
      assert Fixture.classify(:exact) == :exact
      assert Contract.stop(existing).checks[check].events == [{{:call, mfa, [:exact]}, self()}]
    after
      Process.flag(:trap_exit, previous)
    end
  end

  @tag :tmp_dir
  test "activation diagnostic records exact pattern counts and startup spans without changing coverage",
       context do
    check()
    qa = Path.expand("../qa", __DIR__)
    output = Path.join(context.tmp_dir, "phases.json")
    ebin = Contract |> :code.which() |> to_string() |> Path.dirname()
    script = Path.join(context.tmp_dir, "run.exs")

    File.write!(script, """
    Code.require_file(#{inspect(Path.join(qa, "trace-activation-check.exs"))})
    alias Bylaw.Contract.StructuralExample, as: Fixture
    mfa = {Fixture, :classify, 1}
    {:ok, observer} = Bylaw.Contract.start([Fixture], checks: [{BylawTraceActivationCheck, calls: [mfa], returns: [mfa]}])
    :exact = Fixture.classify(:exact)
    coverage = Bylaw.Contract.stop(observer)
    :complete = Map.get(coverage, :status, :complete)
    [{{:call, ^mfa, [:exact]}, caller}, {{:return, ^mfa, :exact}, caller}] = coverage.checks[BylawTraceActivationCheck].events
    true = caller == self()
    """)

    {log, status} =
      System.cmd(
        "elixir",
        ["-pa", ebin, "-r", Path.join(qa, "trace-activation-diagnostic.exs"), script],
        env: [{"BYLAW_TRACE_PHASE_OUTPUT", output}],
        stderr_to_stdout: true
      )

    assert status == 0, log
    spans = output |> File.read!() |> JSON.decode!()

    assert MapSet.new(spans, & &1["function"]) ==
             MapSet.new(
               ~w(start_runtime start_process_worker start_trace_session create_session configure_session configure_patterns configure_process_scope queue_budget_start stop_trace)
             )

    [activation] = Enum.filter(spans, &(&1["function"] == "start_runtime"))
    [patterns] = Enum.filter(spans, &(&1["function"] == "configure_patterns"))

    assert patterns["details"] == %{
             "calls" => 1,
             "returns" => 1,
             "patterns" => 1,
             "scope" => "local"
           }

    assert activation["started_us"] <= patterns["started_us"]
    assert patterns["finished_us"] <= activation["finished_us"]
    assert patterns["duration_us"] >= 0
  end

  @tag :tmp_dir
  test "activation scaling probe completes first and repeated nonempty observation windows",
       context do
    module = Module.concat(__MODULE__, ScalingFixture)
    source = Path.join(context.tmp_dir, "fixture.ex")

    File.write!(source, """
    defmodule #{inspect(module)} do
      @moduledoc false
      @doc false
      @spec f1(term()) :: term()
      def f1(value), do: value
    end
    """)

    [{^module, beam}] = Code.compile_file(source)

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

    File.write!(Path.join(context.tmp_dir, Atom.to_string(module) <> ".beam"), beam)
    config = Path.join(context.tmp_dir, "fixture.json")
    File.write!(config, JSON.encode!(%{modules: [Atom.to_string(module)], functions: 1}))
    output = Path.join(context.tmp_dir, "result.json")
    ebin = Contract |> :code.which() |> to_string() |> Path.dirname()
    probe = Path.expand("../qa/trace-activation-probe.exs", __DIR__)

    {log, status} =
      System.cmd("elixir", ["-pa", ebin, "-pa", context.tmp_dir, probe],
        env: [
          {"BYLAW_OVERHEAD_EBIN", ebin},
          {"BYLAW_TRACE_FIXTURE", config},
          {"BYLAW_TRACE_COUNT", "1"},
          {"BYLAW_TRACE_MODE", "both"},
          {"BYLAW_TRACE_OUTPUT", output}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, log
    %{"cycles" => [first, repeated]} = output |> File.read!() |> JSON.decode!()

    for cycle <- [first, repeated] do
      assert cycle["events"] == 2
      assert cycle["complete"] and cycle["cleanup"] and cycle["exact_events"]
      assert cycle["exact_patterns"] and cycle["caller_identity"]
      assert cycle["queue_limit"] == 4096
    end

    assert first["coverage_sha256"] == repeated["coverage_sha256"]
    assert first["report_sha256"] == repeated["report_sha256"]
  end

  defp check do
    assert Code.ensure_loaded?(BylawTraceActivationCheck)
    BylawTraceActivationCheck
  end

  defp worker_state(observer) do
    [worker] = :sys.get_state(observer).workers
    :sys.get_state(worker)
  end

  defp flush(observer) do
    session = worker_state(observer).session
    reference = :trace.delivered(session, :all)
    assert_receive {:trace_delivered, :all, ^reference}
    worker_state(observer)
  end

  defp stop_if_alive(observer) do
    if Process.alive?(observer), do: Contract.stop(observer)
  end
end
