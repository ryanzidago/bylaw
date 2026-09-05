[project, root, output] = System.argv()

{path, before_fragment, after_fragment, expected, unsupported_path} =
  case project do
    "ecto" ->
      {"lib/ecto/repo/assoc.ex", "def query([], _assocs, _sources, _fun), do: []",
       "def query([], _assocs, _sources, _fun), do: [:changed]", {Ecto.Repo.Assoc, :query, 4},
       "lib/ecto/uuid.ex"}

    "livebook" ->
      {"lib/livebook/utils/time.ex", "when seconds <= 4 do", "when seconds <= 3 do",
       {Livebook.Utils.Time, :duration_in_words, 1}, "lib/livebook/text/delta/operation.ex"}
  end

source = File.read!(Path.join(root, path))
[_, _] = String.split(source, before_fragment)
changed = String.replace(source, before_fragment, after_fragment)
before = %{path => source}
{:ok, selected} = Bylaw.Contract.SourceSelection.select(before, %{path => changed})
true = selected == MapSet.new([expected])
{:ok, unchanged} = Bylaw.Contract.SourceSelection.select(before, before)
true = Enum.empty?(unchanged)

{:ok, moved} =
  Bylaw.Contract.SourceSelection.select(before, %{"moved.ex" => "# shifted source\n" <> source})

true = Enum.empty?(moved)

unsupported_source = File.read!(Path.join(root, unsupported_path))
unsupported = %{unsupported_path => unsupported_source}
{:error, reasons} = Bylaw.Contract.SourceSelection.select(unsupported, unsupported)
true = Enum.any?(reasons, &(&1.code == :unsupported_definition_context))

result = %{
  project: project,
  path: path,
  source_sha256: Base.encode16(:crypto.hash(:sha256, source), case: :lower),
  selected:
    Enum.map(selected, fn {module, function, arity} ->
      %{module: inspect(module), function: function, arity: arity}
    end),
  unchanged_empty: true,
  moved_empty: true,
  unresolved: %{path: unsupported_path, reasons: reasons},
  elixir: System.version(),
  otp: System.otp_release()
}

File.write!(output, :json.encode(result) |> IO.iodata_to_binary())

IO.puts(
  "#{project}: exact changed function, unchanged/moved scope, and unresolved macro context verified"
)
