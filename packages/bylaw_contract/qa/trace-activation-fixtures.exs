[output] = System.argv()
ebin = Path.join(output, "ebin")
File.mkdir_p!(ebin)
Code.compiler_options(debug_info: true)

modules =
  for index <- 1..128 do
    module = Module.concat(BylawTraceFixture, "Module#{index}")
    path = Path.join(output, "module#{index}.ex")

    definitions =
      for function <- 1..64 do
        """
        @doc false
        @spec f#{function}(term()) :: term()
        def f#{function}(value), do: value
        """
      end

    source =
      "defmodule #{inspect(module)} do\n@moduledoc false\n#{Enum.join(definitions, "\n")}end\n"

    File.write!(path, source)
    [{^module, beam}] = Code.compile_file(path)
    File.write!(Path.join(ebin, Atom.to_string(module) <> ".beam"), beam)
    for function <- 1..64, do: :input = apply(module, String.to_atom("f#{function}"), [:input])
    Atom.to_string(module)
  end

File.write!(
  Path.join(output, "config.json"),
  JSON.encode!(%{modules: modules, functions: 64}) <> "\n"
)
