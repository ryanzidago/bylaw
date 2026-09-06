# Diagnostic only: wrap selected functions in source compiled in memory. Never use
# these timings as unprofiled baseline timings. No inspected application is edited.
defmodule BylawPerformancePhaseProbe do
  @doc false
  @spec require_tests(list(Path.t()), keyword()) :: term()
  def require_tests(files, options) do
    details = %{
      test_file_count: length(files),
      max_requires:
        Keyword.get_lazy(options, :max_concurrency, fn ->
          max(:erlang.system_info(:schedulers_online), 2)
        end)
    }

    measure(
      {"Mix.Compilers.Test", :require, 2},
      fn -> Kernel.ParallelCompiler.require(files, options) end,
      details
    )
  end

  @doc false
  @spec measure(term(), (-> term()), map()) :: term()
  def measure(mfa, function, details \\ %{}) do
    started = System.monotonic_time(:microsecond)

    if mfa == {"trace_worker.ex", :start_runtime, 1} do
      send(BylawPerformanceQueueSampler, {:watch, self()})
    end

    try do
      function.()
    after
      finished = System.monotonic_time(:microsecond)

      :ets.insert(
        __MODULE__,
        {System.unique_integer([:positive]), inspect(self()), inspect(mfa), started, finished,
         details}
      )
    end
  end

  @doc false
  @spec sample_queues(map()) :: :ok
  def sample_queues(workers) do
    workers =
      Map.new(workers, fn {pid, values} ->
        sampled =
          case Process.info(pid, :message_queue_len) do
            {:message_queue_len, count} ->
              %{peak: max(count, values.peak), samples: values.samples + 1}

            nil ->
              values
          end

        {pid, sampled}
      end)

    receive do
      {:watch, pid} ->
        sample_queues(Map.put_new(workers, pid, %{peak: 0, samples: 0}))

      {:snapshot, recipient} ->
        send(
          recipient,
          {:queue_peaks, Map.new(workers, fn {pid, value} -> {inspect(pid), value} end)}
        )

        :ok
    after
      5 -> sample_queues(workers)
    end
  end
end

caller = self()
queue_sampler = spawn(fn -> BylawPerformancePhaseProbe.sample_queues(%{}) end)
Process.register(queue_sampler, BylawPerformanceQueueSampler)

owner =
  spawn(fn ->
    :ets.new(BylawPerformancePhaseProbe, [:named_table, :public, :ordered_set])
    send(caller, :phase_table_ready)

    receive do
      {:snapshot, recipient} ->
        send(recipient, {:phase_spans, :ets.tab2list(BylawPerformancePhaseProbe)})
    end
  end)

receive do: (:phase_table_ready -> :ok)
Code.prepend_path(System.fetch_env!("BYLAW_OVERHEAD_EBIN"))
Code.compiler_options(ignore_module_conflict: true)

functions = %{
  "structural_coverage.ex" => ~w(load shadow_forms compile_forms start_shadow stop_shadow)a,
  "specs.ex" => [:load],
  "compiler_inference.ex" => [:load],
  "check/function_clauses.ex" => [:init],
  "check/typespec.ex" => [:init],
  "check/elixir_compiler.ex" => [:init],
  "trace_worker.ex" => [:start_runtime, :stop_trace],
  "tracer.ex" => [:start_link, :stop]
}

for {file, names} <- functions do
  path = Path.expand("../lib/bylaw/contract/#{file}", __DIR__)
  ast = path |> File.read!() |> Code.string_to_quoted!(file: path)

  instrumented =
    Macro.prewalk(ast, fn
      {kind, metadata, [head, [do: body]]} = definition when kind in [:def, :defp] ->
        call =
          case head do
            {:when, _, [call | _]} -> call
            call -> call
          end

        {name, _, arguments} = call

        if name in names do
          label = {file, name, length(arguments || [])}

          wrapped =
            quote do
              BylawPerformancePhaseProbe.measure(unquote(Macro.escape(label)), fn ->
                unquote(body)
              end)
            end

          {kind, metadata, [head, [do: wrapped]]}
        else
          definition
        end

      other ->
        other
    end)

  Code.compile_quoted(instrumented, path)
end

# Native Mix still controls loading and execution. Only its require call is timed.
mix_source = Path.join(to_string(:code.lib_dir(:mix)), "lib/mix/compilers/test.ex")

if File.regular?(mix_source) do
  mix_ast = mix_source |> File.read!() |> Code.string_to_quoted!(file: mix_source)

  mix_ast =
    Macro.postwalk(mix_ast, fn
      {{:., _, [{:__aliases__, _, [:Kernel, :ParallelCompiler]}, :require]}, _, [files, options]} ->
        quote do
          BylawPerformancePhaseProbe.require_tests(unquote(files), unquote(options))
        end

      other ->
        other
    end)

  Code.compile_quoted(mix_ast, mix_source)
else
  raise "Installed Mix source is needed to time the native require boundary"
end

Code.compiler_options(ignore_module_conflict: false)

System.at_exit(fn _ ->
  send(owner, {:snapshot, self()})
  send(queue_sampler, {:snapshot, self()})

  queue_peaks =
    receive do
      {:queue_peaks, peaks} -> peaks
    after
      5_000 -> raise "queue sampler did not respond"
    end

  entries =
    receive do
      {:phase_spans, entries} -> entries
    after
      5_000 -> raise "phase collector did not respond"
    end

  spans =
    for {_, pid, function, started, finished, details} <- entries do
      %{
        pid: pid,
        function: function,
        started_us: started,
        finished_us: finished,
        duration_us: finished - started,
        details: details
      }
    end

  File.write!(System.fetch_env!("BYLAW_PHASE_OUTPUT"), JSON.encode!(spans) <> "\n")

  if output = System.get_env("BYLAW_QUEUE_OUTPUT") do
    File.write!(output, JSON.encode!(%{interval_ms: 5, workers: queue_peaks}) <> "\n")
  end
end)
