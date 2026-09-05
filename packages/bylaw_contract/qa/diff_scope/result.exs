[path] = System.argv()
Code.prepend_path(System.fetch_env!("BYLAW_DIFF_EBIN"))
result = path |> File.read!() |> :erlang.binary_to_term()
if Map.has_key?(result, :error), do: raise("selection error: #{inspect(result.error)}")
coverage = result.coverage

selection =
  Map.update!(result.selection, :selected, fn
    :all -> "all"
    set -> Enum.map(Enum.sort(set), fn {m, f, a} -> "#{inspect(m)}.#{f}/#{a}" end)
  end)

result = result |> Map.delete(:coverage) |> Map.put(:selection, selection)

result =
  if coverage,
    do:
      Map.merge(result, %{
        summary: Bylaw.Contract.summary(coverage),
        target_counts:
          Map.new(
            [
              :input_classes,
              :boundaries,
              :return_alternatives,
              :compiler_return_alternatives,
              :clauses,
              :arities
            ],
            &{&1, length(Map.fetch!(coverage, &1))}
          ),
        incomplete: Map.get(coverage, :incomplete, [])
      }),
    else: result

json = fn value, encoder ->
  cond do
    is_struct(value) ->
      :json.encode_value(inspect(value), encoder)

    is_atom(value) and value not in [nil, true, false] ->
      :json.encode_value(Atom.to_string(value), encoder)

    is_tuple(value) ->
      :json.encode_value(inspect(value), encoder)

    true ->
      :json.encode_value(value, encoder)
  end
end

IO.puts(:json.encode(result, json))
