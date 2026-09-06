# Run from packages/bylaw_contract; parse declarations without loading test code.
rows =
  Enum.flat_map(Path.wildcard("test/*_test.exs"), fn file ->
    source = File.read!(file)
    [_, module_name] = Regex.run(~r/^defmodule (\S+) do/m, source)
    ast = Code.string_to_quoted!(source)

    {_, tests} =
      Macro.prewalk(ast, [], fn
        {:test, metadata, [name | _]} = node, tests when is_binary(name) ->
          row = %{
            module: "Elixir." <> module_name,
            name: "test " <> name,
            file: file,
            line: metadata[:line]
          }

          {node, [row | tests]}

        node, tests ->
          {node, tests}
      end)

    tests
  end)

rows
|> Enum.sort_by(&{&1.module, &1.name})
|> JSON.encode!()
|> IO.puts()
