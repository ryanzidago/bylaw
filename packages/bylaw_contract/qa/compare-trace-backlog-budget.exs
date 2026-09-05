# Decode only trusted, locally generated captures from trace-backlog-budget.exs.
[root, output] = System.argv()
manifest = root |> Path.join("manifest.json") |> File.read!() |> JSON.decode!()

expected =
  for mode <- manifest["modes"],
      speed <- manifest["speeds"],
      {variant, limit} <- manifest["variants"],
      repeat <- 1..manifest["repeats"],
      into: %{},
      do: {"#{mode}--#{speed}--#{variant}--#{repeat}", %{mode: mode, speed: speed, limit: limit}}

results =
  for path <- Path.wildcard(Path.join(root, "*.etf")),
      into: %{},
      do: {Path.basename(path, ".etf"), path |> File.read!() |> :erlang.binary_to_term()}

true = MapSet.new(Map.keys(results)) == MapSet.new(Map.keys(expected))

trials =
  for {name, result} <- Enum.sort(results) do
    true = Map.take(result, [:mode, :speed, :limit]) == expected[name]
    true = length(result.cycles) == manifest["cycles"]
    os = root |> Path.join(name <> ".os.json") |> File.read!() |> JSON.decode!()
    "complete" = os["status"]
    0 = os["exit_code"]

    for cycle <- result.cycles do
      if result.limit in [0, 4096], do: :complete = cycle.status
      if result.limit == 64 and result.speed == "paused", do: :incomplete = cycle.status
    end

    rows =
      root
      |> Path.join(name <> ".jsonl")
      |> File.read!()
      |> String.split("\n")
      |> Enum.filter(&String.starts_with?(&1, "{"))
      |> Enum.map(&JSON.decode!/1)

    phases =
      Map.new(rows, fn row -> {row["phase"], Map.take(row, ["beam", "workers", "wall_us"])} end)

    Map.merge(result, %{name: name, os_peak: os["peak_footprint"], phases: phases})
  end

for mode <- manifest["modes"] do
  hashes =
    for trial <- trials,
        trial.mode == mode,
        cycle <- trial.cycles,
        cycle.status == :complete,
        do: {cycle.coverage_hash, cycle.report_hash}

  [_] = Enum.uniq(hashes)
  IO.inspect({mode, length(hashes)}, label: "equal complete coverage and reports")
end

summary = %{manifest: manifest, trials: trials}
File.write!(output, JSON.encode!(summary))

IO.inspect(Enum.frequencies(for trial <- trials, cycle <- trial.cycles, do: cycle.status),
  label: "cycle outcomes"
)
