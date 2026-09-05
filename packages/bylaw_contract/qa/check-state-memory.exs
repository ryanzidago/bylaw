# elixir qa/check-state-memory.exs PACKAGE_ROOT LIVEBOOK_ROOT MODE MODULE OUTPUT
[package, project, mode, name, output] = System.argv()

{:ok, _, _} =
  Kernel.ParallelCompiler.compile(Path.wildcard(Path.join(package, "lib/**/*.ex")),
    return_diagnostics: true
  )

Code.prepend_paths(Path.wildcard(Path.join(project, "_build/test/lib/*/ebin")))
module = String.to_atom("Elixir." <> name)

check =
  case mode do
    "typespec" -> Bylaw.Contract.Check.Typespec
    "structural" -> Bylaw.Contract.Check.FunctionClauses
  end

word_size = :erlang.system_info(:wordsize)

measure = fn state ->
  %{
    shared_bytes: :erts_debug.size(state) * word_size,
    flat_bytes: :erts_debug.flat_size(state) * word_size,
    classifier_bytes: :erts_debug.flat_size(Map.get(state, :classifiers, [])) * word_size
  }
end

initial =
  (fn ->
     {:ok, state, _} = check.init([module], [], %{claims: MapSet.new()})
     sizes = measure.(state)
     :ok = check.terminate(state)
     sizes
   end).()

{:ok, tracer} = Bylaw.Contract.start([module], checks: [check])
[worker] = :sys.get_state(tracer).workers
parent = self()

:sys.replace_state(worker, fn state ->
  send(parent, {:worker_size, measure.(state.runtime.state)})
  state
end)

worker_size =
  receive do
    {:worker_size, sizes} -> sizes
  end

case module do
  Livebook.Notebook -> true = module.valid_file_entry_name?("notes.txt")
  Livebook.Text.Delta.Operation -> {{:retain, 2}, {:retain, 2}} = module.split_at({:retain, 4}, 2)
end

coverage = Bylaw.Contract.stop(tracer)
{:ok, device} = StringIO.open("")
Bylaw.Contract.print_report(coverage, device)
{_, report} = StringIO.contents(device)
StringIO.close(device)
result = %{coverage: coverage, summary: Bylaw.Contract.summary(coverage), report: report}
File.write!(output, :erlang.term_to_binary(result, [:deterministic]))

IO.inspect(
  %{
    runtime: {System.version(), System.otp_release()},
    initial: initial,
    worker: worker_size,
    coverage: measure.(coverage),
    summary: Bylaw.Contract.summary(coverage)
  },
  limit: :infinity
)
