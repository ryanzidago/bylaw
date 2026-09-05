# elixir qa/compare-memory-coverage.exs OUTPUT_DIRECTORY
# Decode only trusted, locally generated captures from default-check-memory.exs.
root = hd(System.argv())

normalize = fn normalize, value, directory ->
  cond do
    is_binary(value) ->
      String.replace(value, directory, "<fixture>")

    is_list(value) ->
      Enum.map(value, &normalize.(normalize, &1, directory))

    is_tuple(value) ->
      value
      |> Tuple.to_list()
      |> Enum.map(&normalize.(normalize, &1, directory))
      |> List.to_tuple()

    is_map(value) ->
      Map.new(:maps.to_list(value), fn {k, v} ->
        {normalize.(normalize, k, directory), normalize.(normalize, v, directory)}
      end)

    true ->
      value
  end
end

for mode <- ["typespec", "structural", "default"] do
  results =
    for repeat <- 1..3, speed <- ["running", "slow", "paused"] do
      path = Path.join(root, "#{mode}-#{speed}-#{repeat}.etf")
      result = path |> File.read!() |> :erlang.binary_to_term()
      coverage = normalize.(normalize, result.coverage, path <> ".fixture")
      :crypto.hash(:sha256, :erlang.term_to_binary(coverage, [:deterministic])) |> Base.encode16()
    end

  [hash] = Enum.uniq(results)
  IO.inspect({mode, length(results), hash}, label: "identical normalized coverage")
end
