# Compare sorted target metadata in bounded workers, one module at a time.
# elixir qa/typespec-metadata.exs PACKAGE_ROOT PROJECT_ROOT APP OUTPUT
[package, project, app_name, output] = System.argv()

for file <- ["type_matcher.ex", "type_expansion.ex", "specs.ex"] do
  path = Path.join([package, "lib/bylaw/contract", file])
  if File.exists?(path), do: Code.require_file(path)
end

Code.prepend_paths(Path.wildcard(Path.join(project, "_build/test/lib/*/ebin")))
app = String.to_atom(app_name)
:ok = Application.load(app)
{:ok, modules} = :application.get_key(app, :modules)

results =
  Enum.map(modules, fn module ->
    parent = self()

    {pid, ref} =
      :erlang.spawn_opt(
        fn ->
          state = Bylaw.Contract.Specs.load([module])

          metadata =
            Map.new(
              Map.take(state, [:input_classes, :boundaries, :return_alternatives]),
              fn {kind, targets} ->
                {kind, Enum.map(targets, &Map.delete(&1, :match_type))}
              end
            )

          send(parent, {:done, metadata})
        end,
        [:monitor, {:max_heap_size, %{size: 20_000_000, kill: true, error_logger: false}}]
      )

    receive do
      {:done, metadata} ->
        Process.demonitor(ref, [:flush])
        metadata

      {:DOWN, ^ref, :process, ^pid, reason} ->
        raise "inspection stopped: #{inspect(reason)}"
    after
      30_000 ->
        Process.exit(pid, :kill)
        raise "inspection timed out"
    end
  end)

metadata =
  Map.new([:input_classes, :boundaries, :return_alternatives], fn kind ->
    {kind, results |> Enum.flat_map(&Map.fetch!(&1, kind)) |> Enum.sort()}
  end)

File.write!(output, :erlang.term_to_binary(metadata, [:deterministic]))

IO.inspect(
  Map.new(metadata, fn {kind, targets} ->
    {kind, {length(targets), Enum.count(targets, & &1.supported?)}}
  end)
)
