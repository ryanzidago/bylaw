[mode, producers, total, shape, size, pacing, output] = System.argv()
producers = String.to_integer(producers)
total = String.to_integer(total)
size = String.to_integer(size)
Code.prepend_path(System.fetch_env!("BYLAW_LIMIT_EBIN"))
directory = System.fetch_env!("BYLAW_LIMIT_FIXTURE")
File.mkdir_p!(directory)
source = Path.join(directory, "fixture.ex")

File.write!(source, """
defmodule ThroughputLimitFixture do
  @spec route(:left | :right, binary() | list(integer())) :: :left | :right
  def route(:left, payload) when is_binary(payload) or is_list(payload), do: :left
  def route(:right, payload) when is_binary(payload) or is_list(payload), do: :right
end
""")

{:ok, _, _} =
  Kernel.ParallelCompiler.compile_to_path([source], directory, return_diagnostics: true)

Code.prepend_path(directory)

checks =
  case mode do
    "typespec" -> [Bylaw.Contract.Check.Typespec]
    "structural" -> [Bylaw.Contract.Check.FunctionClauses]
    "default" -> [Bylaw.Contract.Check.Typespec, Bylaw.Contract.Check.FunctionClauses]
  end

payload =
  case shape do
    "binary" -> :binary.copy(<<1>>, size)
    "list" -> List.duplicate(1, size)
  end

mfa = {ThroughputLimitFixture, :route, 2}

cycles =
  for cycle <- 1..2 do
    {:ok, observer} = Bylaw.Contract.start([ThroughputLimitFixture], checks: checks)
    workers = :sys.get_state(observer).workers
    sessions = Enum.map(workers, &:sys.get_state(&1).session)

    linked =
      for worker <- workers,
          {:links, pids} = Process.info(worker, :links),
          pid <- pids,
          pid != observer,
          do: pid

    parent = self()
    per_producer = div(total, producers)
    true = rem(per_producer, 2) == 0

    children =
      for _ <- 1..producers do
        spawn_monitor(fn ->
          receive do
            :go -> :ok
          end

          for index <- 1..per_producer do
            key = if rem(index, 2) == 0, do: :left, else: :right
            ^key = ThroughputLimitFixture.route(key, payload)
            if pacing == "paced" and rem(index, 8) == 0, do: Process.sleep(5)
          end

          send(parent, {:done, self()})
        end)
      end

    started = System.monotonic_time(:microsecond)
    for {pid, _} <- children, do: send(pid, :go)

    for {pid, ref} <- children do
      receive do
        {:done, ^pid} -> :ok
      after
        20_000 -> raise "producer timeout"
      end

      receive do
        {:DOWN, ^ref, :process, ^pid, :normal} -> :ok
      after
        20_000 -> raise "producer did not exit"
      end
    end

    producer_us = System.monotonic_time(:microsecond) - started
    coverage = Bylaw.Contract.stop(observer)
    stopped_us = System.monotonic_time(:microsecond) - started
    true = Enum.all?(workers ++ linked, &(not Process.alive?(&1)))

    for session <- sessions do
      try do
        :trace.info(session, mfa, :traced)
        raise "session leaked"
      rescue
        ArgumentError -> :ok
      end
    end

    status = Map.get(coverage, :status, :complete)

    if status == :complete do
      if mode != "structural" do
        ^total = Map.fetch!(coverage.calls, mfa)
        ^total = Map.fetch!(coverage.return_events, mfa)

        expected_inputs = %{
          {1, ":left"} => div(total, 2),
          {1, ":right"} => div(total, 2),
          {2, "binary()"} => if(shape == "binary", do: total, else: 0),
          {2, "[integer()]"} => if(shape == "list", do: total, else: 0)
        }

        ^expected_inputs =
          Map.new(
            coverage.input_classes,
            &{{&1.argument, &1.label}, Map.get(coverage.hits, &1.id, 0)}
          )

        expected_returns = %{":left" => div(total, 2), ":right" => div(total, 2)}

        ^expected_returns =
          Map.new(coverage.return_alternatives, &{&1.label, Map.get(coverage.hits, &1.id, 0)})
      end

      if mode != "typespec" do
        ^total = Map.fetch!(coverage.arity_calls, mfa)
        2 = length(coverage.clauses)

        for clause <- coverage.clauses do
          expected = %{
            selected: div(total, 2),
            head_matches: div(total, 2),
            guard_passes: div(total, 2),
            guard_rejections: 0
          }

          ^expected = Map.fetch!(coverage.clause_outcomes, clause.id)
        end
      end
    else
      %{status: :incomplete} = Bylaw.Contract.summary(coverage)
      true = Enum.all?(coverage.incomplete, &(&1.limit == 4096 and &1.observed > 4096))
    end

    {:ok, device} = StringIO.open("")
    Bylaw.Contract.print_report(coverage, device, colors: false)
    {_, report} = StringIO.contents(device)
    StringIO.close(device)
    if status == :incomplete, do: false = String.contains?(report, "Missed")

    hash = fn term ->
      :crypto.hash(:sha256, :erlang.term_to_binary(term, [:deterministic])) |> Base.encode16()
    end

    %{
      cycle: cycle,
      status: status,
      producer_us: producer_us,
      stopped_us: stopped_us,
      calls: Map.get(coverage.calls, mfa, 0),
      returns: Map.get(coverage.return_events, mfa, 0),
      structural_calls: Map.get(coverage.arity_calls, mfa, 0),
      incomplete: Map.get(coverage, :incomplete, []),
      coverage_hash: hash.(coverage),
      report_hash: hash.(report),
      exact_when_complete: true,
      cleanup_verified: true
    }
  end

File.write!(
  output,
  JSON.encode!(%{
    mode: mode,
    producers: producers,
    total: total,
    shape: shape,
    size: size,
    pacing: pacing,
    cycles: cycles
  })
)
