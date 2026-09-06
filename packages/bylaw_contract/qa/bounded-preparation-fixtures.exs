[output] = System.argv()
Code.compiler_options(debug_info: true)

configs = [
  {4, 1, 3, 0},
  {16, 1, 3, 0},
  {64, 1, 3, 0},
  {4, 4, 3, 0},
  {4, 16, 3, 0},
  {4, 1, 6, 0},
  {4, 1, 12, 0},
  {4, 1, 3, 2},
  {4, 1, 3, 8}
]

for {modules, functions, clauses, guards} <- configs do
  name = "m#{modules}-f#{functions}-c#{clauses}-g#{guards}"
  directory = Path.join(output, name)
  ebin = Path.join(directory, "ebin")
  File.mkdir_p!(ebin)
  extra_guards = Enum.take([2, 3, 5, 7, 11, 13, 17, 19], guards)

  for index <- 1..modules do
    module = Module.concat(BylawBoundedFixture, "Module#{index}")
    path = Path.join(directory, "module#{index}.ex")

    definitions =
      for function <- 1..functions do
        clauses_source =
          for position <- 1..(clauses - 1) do
            conditions =
              ["is_integer(value)", "value >= #{clauses - 1 - position}"] ++
                Enum.map(extra_guards, &":erlang.rem(value, #{&1}) >= 0")

            "def classify#{function}(value, mode) when #{Enum.join(conditions, " and ")}, do: {#{position}, mode}"
          end

        """
        @doc false
        @spec classify#{function}(term(), atom()) :: {integer() | :fallback, atom()}
        def classify#{function}(value, mode \\\\ :default)
        #{Enum.join(clauses_source, "\n")}
        def classify#{function}(_, mode), do: {:fallback, mode}
        """
      end

    source =
      "defmodule #{inspect(module)} do\n@moduledoc false\n#{Enum.join(definitions, "\n")}\nend\n"

    File.write!(path, source)
    :code.purge(module)
    :code.delete(module)
    [{^module, beam}] = Code.compile_file(path)
    File.write!(Path.join(ebin, Atom.to_string(module) <> ".beam"), beam)

    for function <- 1..functions, value <- [-1, 0, 1, 10, :atom] do
      expected =
        if is_integer(value) and value >= 0,
          do: {max(1, clauses - 1 - value), :default},
          else: {:fallback, :default}

      ^expected = apply(module, String.to_atom("classify#{function}"), [value])
    end
  end

  File.write!(
    Path.join(directory, "config.json"),
    JSON.encode!(%{
      name: name,
      modules: modules,
      functions: functions,
      clauses: clauses,
      guards: guards
    }) <> "\n"
  )
end
