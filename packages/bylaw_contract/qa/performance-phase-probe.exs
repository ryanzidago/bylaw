# Diagnostic only: wrap selected functions in source compiled in memory. Never use
# these timings as unprofiled baseline timings. No inspected application is edited.
defmodule BylawPerformancePhaseProbe do
  def measure(mfa, function) do
    started = System.monotonic_time(:microsecond)

    try do
      function.()
    after
      finished = System.monotonic_time(:microsecond)

      :ets.insert(
        __MODULE__,
        {System.unique_integer([:positive]), inspect(self()), inspect(mfa), started, finished}
      )
    end
  end
end

caller = self()

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
      {{:., _, [{:__aliases__, _, [:Kernel, :ParallelCompiler]}, :require]}, _, _} = call ->
        quote do
          BylawPerformancePhaseProbe.measure({"Mix.Compilers.Test", :require, 2}, fn ->
            unquote(call)
          end)
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

  entries =
    receive do
      {:phase_spans, entries} -> entries
    after
      5_000 -> raise "phase collector did not respond"
    end

  spans =
    for {_, pid, function, started, finished} <- entries do
      %{
        pid: pid,
        function: function,
        started_us: started,
        finished_us: finished,
        duration_us: finished - started
      }
    end

  File.write!(System.fetch_env!("BYLAW_PHASE_OUTPUT"), JSON.encode!(spans) <> "\n")
end)
