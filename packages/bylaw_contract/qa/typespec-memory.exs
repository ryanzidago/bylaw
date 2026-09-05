# Fresh VM: elixir qa/typespec-memory.exs PACKAGE_ROOT synthetic
# Or: elixir qa/typespec-memory.exs PACKAGE_ROOT real PROJECT_ROOT Module.Name
[package, mode | args] = System.argv()
base = Path.join(package, "lib/bylaw/contract")

for file <- ["type_matcher.ex", "type_expansion.ex", "specs.ex", "check.ex", "check/typespec.ex"] do
  path = Path.join(base, file)
  if File.exists?(path), do: Code.require_file(path)
end

measure = fn module ->
  {:ok, state, _} = Bylaw.Contract.Check.Typespec.init([module], [], %{claims: MapSet.new()})
  coverage = Bylaw.Contract.Check.Typespec.coverage(state)
  word_size = :erlang.system_info(:wordsize)

  metadata =
    Map.new(Map.take(coverage, [:input_classes, :boundaries, :return_alternatives]), fn {kind,
                                                                                         targets} ->
      {kind, Enum.map(targets, &Map.delete(&1, :match_type))}
    end)

  %{
    targets: length(coverage.input_classes),
    supported: Enum.count(coverage.input_classes, & &1.supported?),
    shared_bytes: :erts_debug.size(state) * word_size,
    flat_bytes: :erts_debug.flat_size(state) * word_size,
    metadata_sha256:
      :crypto.hash(:sha256, :erlang.term_to_binary(metadata, [:deterministic])) |> Base.encode16(),
    warnings: state.warnings
  }
end

IO.inspect({System.version(), System.otp_release()}, label: "runtime")

case {mode, args} do
  {"synthetic", []} ->
    directory =
      Path.join(System.tmp_dir!(), "bylaw-typespec-#{System.unique_integer([:positive])}")

    File.mkdir_p!(directory)
    Code.prepend_path(directory)

    try do
      for depth <- [4, 8, 12] do
        module = Module.concat(["BylawMemoryDepth#{depth}"])

        definitions =
          Enum.map_join(1..depth, "\n", fn index ->
            "@type t#{index}() :: {t#{index - 1}(), t#{index - 1}()}"
          end)

        source = """
        defmodule #{inspect(module)} do
          @type t0() :: integer()
          #{definitions}
          @spec f(t#{depth}()) :: :ok
          def f(_), do: :ok
        end
        """

        [{^module, binary}] = Code.compile_string(source)
        File.write!(Path.join(directory, "#{module}.beam"), binary)
        :code.delete(module)
        :code.purge(module)
        {:module, ^module} = :code.load_abs(String.to_charlist(Path.join(directory, "#{module}")))
        IO.inspect({depth, measure.(module)})
        :code.delete(module)
        :code.purge(module)
      end
    after
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end

  {"real", [project, name]} ->
    Code.prepend_paths(Path.wildcard(Path.join(project, "_build/test/lib/*/ebin")))
    Code.prepend_paths(Path.wildcard(Path.join(project, "_build/dev/lib/*/ebin")))
    IO.inspect(measure.(String.to_atom("Elixir." <> name)))
end
