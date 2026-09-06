# Persist bounded framework-free fixtures before any timed preparation command.
[output] = System.argv()
Code.compiler_options(debug_info: true)

for {modules, body_size} <- [{1, 8}, {1, 64}, {1, 512}, {1, 4096}, {4, 512}, {16, 512}, {64, 512}] do
  directory = Path.join(output, "modules#{modules}-body#{body_size}")
  ebin = Path.join(directory, "ebin")
  File.mkdir_p!(ebin)
  values = Enum.join(1..body_size, ", ")

  for index <- 1..modules do
    module = Module.concat(BylawBodyFixture, "Module#{index}")
    path = Path.join(directory, "module#{index}.ex")

    File.write!(path, """
    defmodule #{inspect(module)} do
      def total(seed) when is_integer(seed), do: Enum.sum([#{values}]) + seed
      def total(:skip), do: 0
    end
    """)

    :code.purge(module)
    :code.delete(module)
    [{^module, binary}] = Code.compile_file(path)
    File.write!(Path.join(ebin, Atom.to_string(module) <> ".beam"), binary)
    expected = div(body_size * (body_size + 1), 2) + 3
    ^expected = apply(module, :total, [3])
    0 = apply(module, :total, [:skip])
  end
end
