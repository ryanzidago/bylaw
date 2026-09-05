Code.require_file("target-plan.exs", __DIR__)
Code.require_file("clause-plan.exs", __DIR__)
[mode, producers, total, size, pacing, directory, output] = System.argv()
producers = String.to_integer(producers)
total = String.to_integer(total)
size = String.to_integer(size)
Code.prepend_path(System.fetch_env!("BYLAW_PRODUCER_EBIN"))
File.mkdir_p!(directory)
source = Path.join(directory, "fixture.ex")

File.write!(source, """
defmodule ProducerCombinedWorkload do
  @spec echo(list(integer())) :: list(integer()) | :unused
  def echo(value), do: value
end
""")

{:ok, _, _} =
  Kernel.ParallelCompiler.compile_to_path([source], directory, return_diagnostics: true)

Code.prepend_path(directory)
{:module, ProducerCombinedWorkload} = Code.ensure_loaded(ProducerCombinedWorkload)
mfa = {ProducerCombinedWorkload, :echo, 1}

payload = List.duplicate(1, size)

observer =
  case mode do
    "baseline" ->
      nil

    "native" ->
      metadata = Bylaw.Contract.Specs.load([ProducerCombinedWorkload])
      [] = metadata.warnings
      [] = metadata.boundaries

      entries =
        Enum.map(metadata.input_classes, &{:call, &1}) ++
          Enum.map(metadata.return_alternatives, &{:return, &1})

      {:ok, plan} = ProducerTargetPlan.compile(entries)
      structural = Bylaw.Contract.StructuralCoverage.load([ProducerCombinedWorkload])
      [] = structural.warnings
      [classifier] = structural.classifiers
      [mfa_classifier] = classifier.mfa_classifiers
      {:ok, clauses} = ProducerClausePlan.compile(mfa_classifier)
      4 = map_size(clauses.slots)

      expected =
        entries
        |> Enum.sort_by(fn {_, target} -> target.id end)
        |> Enum.map(fn {_, target} ->
          case Bylaw.Contract.TypeMatcher.match(payload, target.match_type) do
            :match -> total
            :no_match -> 0
          end
        end)

      resource = ProducerNative.plan(plan.rules, 4096, 4)
      session = :trace.session_create(:producer_combined_workload, {ProducerNative, resource}, [])
      1 = :trace.function(session, mfa, clauses.match_spec, [:local])
      ProducerNative.watch_code_changes(session)
      :trace.process(session, :all, true, [:call])
      {session, resource, expected ++ [total, total, total, 0]}

    "trace" ->
      {:ok, observer} =
        Bylaw.Contract.start([ProducerCombinedWorkload],
          checks: [Bylaw.Contract.Check.Typespec, Bylaw.Contract.Check.FunctionClauses]
        )

      observer
  end

parent = self()

children =
  for _ <- 1..producers do
    spawn_monitor(fn ->
      receive do
        :go -> :ok
      end

      for index <- 1..div(total, producers) do
        ^payload = ProducerCombinedWorkload.echo(payload)
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
    20_000 -> raise "producer failure"
  end
end

producer_us = System.monotonic_time(:microsecond) - started

result =
  case mode do
    "baseline" ->
      %{status: :unobserved}

    "native" ->
      {session, resource, expected} = observer
      :trace.session_destroy(session)
      {^total, ^total} = ProducerNative.counts(resource)
      ^expected = ProducerNative.hits(resource)
      :complete = ProducerNative.status(resource)

      %{
        status: :complete,
        calls: total,
        returns: total,
        classification_counts: expected,
        native_payload_bytes: ProducerNative.bytes(resource)
      }

    "trace" ->
      coverage = Bylaw.Contract.stop(observer)
      status = Map.get(coverage, :status, :complete)

      if status == :complete do
        ^total = Map.fetch!(coverage.calls, mfa)
        ^total = Map.fetch!(coverage.return_events, mfa)
        3 = length(coverage.input_classes)

        for input <- coverage.input_classes do
          expected = if input.partition == :multiple, do: total, else: 0
          ^expected = Map.get(coverage.hits, input.id, 0)
        end

        for target <- coverage.return_alternatives do
          expected = if target.label == ":unused", do: 0, else: total
          ^expected = Map.get(coverage.hits, target.id, 0)
        end

        [clause] = coverage.clauses

        %{head_matches: ^total, guard_passes: ^total, selected: ^total, guard_rejections: 0} =
          Map.fetch!(coverage.clause_outcomes, clause.id)

        ^total = Map.fetch!(coverage.arity_calls, mfa)
        0 = Map.get(coverage.unmatched_clause_calls, mfa, 0)
      else
        true = Enum.any?(coverage.incomplete)
        true = Enum.all?(coverage.incomplete, &(&1.limit == 4096 and &1.observed > 4096))
      end

      target_counts =
        (coverage.input_classes ++ coverage.return_alternatives)
        |> Enum.sort_by(& &1.id)
        |> Enum.map(&Map.get(coverage.hits, &1.id, 0))

      [clause] = coverage.clauses
      outcomes = Map.get(coverage.clause_outcomes, clause.id, %{})

      clause_counts =
        Enum.map(
          [:head_matches, :guard_passes, :selected, :guard_rejections],
          &Map.get(outcomes, &1, 0)
        )

      %{
        status: status,
        classification_counts: target_counts ++ clause_counts,
        calls: Map.get(coverage.calls, mfa, 0),
        returns: Map.get(coverage.return_events, mfa, 0),
        incomplete: Map.get(coverage, :incomplete, [])
      }
  end

stopped_us = System.monotonic_time(:microsecond) - started

File.write!(
  output,
  JSON.encode!(
    Map.merge(result, %{
      mode: mode,
      producers: producers,
      total: total,
      size: size,
      pacing: pacing,
      producer_us: producer_us,
      stopped_us: stopped_us
    })
  )
)
