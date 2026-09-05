# Run with Elixir 1.20.2/OTP 29 and compiled Bylaw on the code path.
# Prints actual values beside inferred-alternative hits; uses only a synthetic fixture.
dir =
  Path.join(System.tmp_dir!(), "bylaw-normalized-clauses-#{System.unique_integer([:positive])}")

File.mkdir_p!(dir)
source = Path.join(dir, "fixture.ex")

File.write!(source, """
defmodule BylawAuditNormalizedClauses do
  def choose({:done, _, _} = value), do: value
  def choose({:discard, value}), do: discard(value)
  def choose({:keep, value}), do: {:keep, value}
  def choose(value), do: discard(value)

  defp discard([]), do: {:done, [], []}
  defp discard(value) when is_list(value) or is_binary(value) do
    key = :binary.compile_pattern(value)
    match = value |> List.wrap() |> Enum.map(&(&1 <> "=")) |> :binary.compile_pattern()
    {:done, key, match}
  end
end
""")

{:ok, _, _} = Kernel.ParallelCompiler.compile_to_path([source], dir, return_diagnostics: true)
Code.prepend_path(dir)
module = BylawAuditNormalizedClauses
loaded = Bylaw.Contract.CompilerInference.load([module])

IO.inspect(Enum.filter(loaded.inference_rules, &(&1.function == :choose)),
  label: "rules",
  limit: :infinity
)

for values <- [[{:keep, []}], [{:discard, []}], [{:done, 0, 0}, {:keep, []}]] do
  {:ok, tracer} = Bylaw.Contract.start([module], checks: [Bylaw.Contract.Check.ElixirCompiler])
  results = Enum.map(values, &module.choose/1)
  c = Bylaw.Contract.stop(tracer)
  IO.inspect({values, results, c.compiler_calls}, label: "call")

  IO.inspect(
    for(
      t <- c.compiler_return_alternatives,
      t.function == :choose,
      do: {t.label, Map.get(c.hits, t.id, 0), MapSet.member?(c.unknown, t.id)}
    ),
    label: "targets"
  )
end

File.rm_rf!(dir)
