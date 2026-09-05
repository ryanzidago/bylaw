[mode, producers, total, size, pacing, directory, output] = System.argv()
producers = String.to_integer(producers)
total = String.to_integer(total)
size = String.to_integer(size)
Code.prepend_path(System.fetch_env!("BYLAW_PRODUCER_EBIN"))
File.mkdir_p!(directory)
source = Path.join(directory, "fixture.ex")

File.write!(source, """
defmodule ProducerListWorkload do
  @spec echo(list(integer())) :: list(integer()) | :unused
  def echo(value), do: value
end
""")

{:ok, _, _} =
  Kernel.ParallelCompiler.compile_to_path([source], directory, return_diagnostics: true)

Code.prepend_path(directory)
{:module, ProducerListWorkload} = Code.ensure_loaded(ProducerListWorkload)
mfa = {ProducerListWorkload, :echo, 1}

observer =
  case mode do
    "baseline" ->
      nil

    "native" ->
      resource = ProducerNative.integer_list(4096)
      session = :trace.session_create(:producer_list_workload, {ProducerNative, resource}, [])
      1 = :trace.function(session, mfa, [{:_, [], [{:return_trace}]}], [:local])
      ProducerNative.watch_code_changes(session)
      :trace.process(session, :all, true, [:call])
      {session, resource}

    "trace" ->
      {:ok, observer} =
        Bylaw.Contract.start([ProducerListWorkload], checks: [Bylaw.Contract.Check.Typespec])

      observer
  end

payload = List.duplicate(1, size)
parent = self()

children =
  for _ <- 1..producers do
    spawn_monitor(fn ->
      receive do
        :go -> :ok
      end

      for index <- 1..div(total, producers) do
        ^payload = ProducerListWorkload.echo(payload)
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
      {session, resource} = observer
      :trace.session_destroy(session)
      {^total, ^total} = ProducerNative.counts(resource)
      [^total, ^total, 0, 0, 0, 0, 0, 0] = ProducerNative.hits(resource)
      :complete = ProducerNative.status(resource)

      %{
        status: :complete,
        calls: total,
        returns: total,
        input_hits: total,
        return_hits: total,
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
      else
        true = Enum.any?(coverage.incomplete)
        true = Enum.all?(coverage.incomplete, &(&1.limit == 4096 and &1.observed > 4096))
      end

      %{
        status: status,
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
