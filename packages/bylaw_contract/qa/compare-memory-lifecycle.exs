# Decode only trusted captures produced by memory-lifecycle.exs.
[root] = System.argv()
manifest = root |> Path.join("manifest.json") |> File.read!() |> JSON.decode!()

results =
  for path <- Path.wildcard(Path.join(root, "*.etf")) do
    result = path |> File.read!() |> :erlang.binary_to_term()
    :complete = result.status

    for cycle <- result.cycles, result.config.mode != "baseline" do
      true = cycle.workers_dead
      true = cycle.encoding.decoded_equal

      if result.config.mode in ["typespec", "default"] do
        1000 = cycle.summary.calls
        if Map.get(result.config, :return_payload, false), do: 1000 = cycle.summary.return_events
      end

      if result.config.mode in ["structural", "default"], do: 1000 = cycle.summary.arity_calls
    end

    {Path.basename(path, ".etf"), result}
  end

expected =
  for repeat <- 1..manifest["repeats"],
      {name, options} <- manifest["cases"],
      mode <- manifest["modes"],
      into: %{} do
    config =
      Map.merge(options, %{
        "mode" => mode,
        "calls" => manifest["calls_per_cycle"],
        "cycles" => manifest["cycles"],
        "return_payload" => manifest["return_payload"]
      })

    {"#{name}--#{mode}--#{repeat}", config}
  end

true = MapSet.new(Map.keys(expected)) == MapSet.new(Enum.map(results, &elem(&1, 0)))

for {name, result} <- results do
  true =
    Map.new(result.config, fn {key, value} -> {Atom.to_string(key), value} end) == expected[name]

  true = length(result.cycles) == manifest["cycles"]
end

for mode <- ["typespec", "structural", "default"] do
  comparable =
    for {name, result} <- results,
        result.config.mode == mode,
        String.starts_with?(name, "base--") or String.starts_with?(name, "speed-") or
          String.starts_with?(name, "producers-"),
        cycle <- result.cycles,
        do: {cycle.coverage_hash, cycle.report_hash}

  [_] = Enum.uniq(comparable)
  IO.inspect({mode, length(comparable)}, label: "equal coverage and reports")
end

expected_trials = manifest["repeats"] * length(manifest["modes"]) * map_size(manifest["cases"])
^expected_trials = length(results)

for {_group, group} <-
      Enum.group_by(results, fn {name, _} -> name |> String.split("--") |> Enum.take(2) end),
    elem(hd(group), 1).config.mode != "baseline" do
  [_] =
    Enum.uniq(
      for {_, result} <- group,
          cycle <- result.cycles,
          do: {cycle.coverage_hash, cycle.report_hash}
    )
end

IO.puts("Complete trials: #{length(results)}")
File.write!(Path.join(root, "results.json"), JSON.encode!(Map.new(results)))
