Code.require_file("runtime.exs", __DIR__)
module = BylawDiffFixture
path = Path.join(System.tmp_dir!(), "bylaw-diff-runtime-#{System.unique_integer([:positive])}")
File.mkdir_p!(path)

functions =
  for index <- 1..12,
      do: "def a#{index}(:zero), do: :zero\ndef a#{index}(:positive), do: :positive"

source = """
defmodule #{inspect(module)} do
  #{Enum.join(functions, "\n")}
  @spec zeta(:zero | :positive) :: :zero | :positive
  def zeta(:zero), do: :zero
  def zeta(:positive), do: :positive
  @type recursive() :: {:node, recursive()}
  @spec unsupported(recursive()) :: :ok
  def unsupported(_), do: :ok
end
"""

source_path = Path.join(path, "fixture.ex")
File.write!(source_path, source)
previous = Code.compiler_options()
Code.compiler_options(infer_signatures: [:elixir])
[{^module, binary}] = Code.compile_file(source_path)
Code.compiler_options(previous)
alias Module.Types.Descr

signature =
  {:infer, nil,
   [
     {[Descr.atom([:zero])], Descr.atom([:zero])},
     {[Descr.atom([:positive])], Descr.atom([:positive])}
   ]}

exports =
  for function <- [:zeta | Enum.map(1..12, &String.to_atom("a#{&1}"))],
      do: {{function, 1}, %{sig: signature}}

{:ok, _, chunks} = :beam_lib.all_chunks(binary)

chunks =
  Enum.map(chunks, fn
    {~c"ExCk", _} -> {~c"ExCk", :erlang.term_to_binary({:elixir_checker_v8, %{exports: exports}})}
    chunk -> chunk
  end)

{:ok, binary} = :beam_lib.build_module(chunks)
File.write!(Path.join(path, "#{module}.beam"), binary)
Code.prepend_path(path)
:code.purge(module)
{:module, ^module} = :code.load_file(module)
selection = MapSet.new([{module, :zeta, 1}, {module, :unsupported, 1}])

try do
  compiler = Bylaw.Contract.Check.ElixirCompiler

  {:ok, baseline, _} =
    Bylaw.Contract.Check.ElixirCompiler.init([module], [], %{claims: MapSet.new()})

  unless map_size(baseline.alternatives_by_mfa) == 10,
    do: raise("baseline did not exercise default cap")

  unless not Map.has_key?(baseline.alternatives_by_mfa, {module, :zeta, 1}),
    do: raise("late function unexpectedly selected")

  Bylaw.Contract.Check.ElixirCompiler.terminate(baseline)
  {:ok, state, _} = compiler.init([module], [], %{claims: MapSet.new(), only: selection})

  try do
    selected = Map.keys(state.alternatives_by_mfa)

    unless {module, :zeta, 1} in selected,
      do:
        raise(
          "selected function absent from compiler instrumentation: #{inspect(state.compiler_warnings)}"
        )

    unless Enum.all?(selected, &MapSet.member?(selection, &1)),
      do: raise("compiler selected out of scope")

    unless Enum.any?(state.instrumented_modules), do: raise("no actual compiler instrumentation")
    :zero = module.zeta(:zero)
    measured = compiler.coverage(state)
    unless measured.compiler_calls[{module, :zeta, 1}] == 1, do: raise("compiler counter missing")
    IO.puts("selection-before-cap: ok")
  after
    compiler.terminate(state)
  end

  for _ <- 1..2 do
    {:ok, tracer} =
      Bylaw.Contract.start([module], BylawDiffScope.Runtime.options(selection))

    :zero = module.zeta(:zero)
    :positive = module.zeta(:positive)
    :positive = Task.async(fn -> module.zeta(:positive) end) |> Task.await()
    :ok = module.unsupported(fn -> :ok end)
    :zero = module.a1(:zero)
    coverage = Bylaw.Contract.stop(tracer)
    unless Map.get(coverage, :status) != :incomplete, do: raise("incomplete observation")

    unless coverage.calls[{module, :zeta, 1}] == 3,
      do: raise("typespec calls #{inspect(coverage.calls)}")

    unless coverage.arity_calls[{module, :zeta, 1}] == 3,
      do: raise("structural calls #{inspect(coverage.arity_calls)}")

    unless Enum.all?(
             coverage.clauses,
             &MapSet.member?(selection, {&1.module, &1.function, &1.arity})
           ),
           do: raise("unselected clauses remain")

    unless Enum.all?(Map.keys(coverage.calls), &MapSet.member?(selection, &1)),
      do: raise("unselected calls observed")

    unless Enum.any?(coverage.input_classes, &(!&1.supported?)),
      do: raise("unknown fixture did not retain unsupported target")

    unless not Process.alive?(tracer), do: raise("tracer not stopped")
  end

  {:ok, {^module, md5}} = :beam_lib.md5(binary)
  unless module.module_info(:md5) == md5, do: raise("loaded module was not restored")

  unless :code.which(module) != ~c"bylaw-compiler-observer",
    do: raise("instrumentation remains loaded")

  IO.puts("counts-unknown-cleanup: ok")
after
  :code.purge(module)
  :code.delete(module)
  Code.delete_path(path)
  File.rm_rf!(path)
end
