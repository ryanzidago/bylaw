defmodule Bylaw.Credo.Check.Testing.NoUnseededRandomness do
  @moduledoc """
  Do not build test data from unseeded randomness, so a failing run can be repeated.

  ## Examples

  Avoid:

        test "keeps the cheapest item" do
          prices = Enum.map(1..5, fn _ -> :rand.uniform(100) end)
          items = Enum.shuffle(Enum.map(prices, &item_fixture(price: &1)))

          assert Menu.cheapest(items).price == Enum.min(prices)
        end

  Prefer:

        property "keeps the cheapest item" do
          check all prices <- list_of(integer(1..100), min_length: 1) do
            items = Enum.map(prices, &item_fixture(price: &1))

            assert Menu.cheapest(items).price == Enum.min(prices)
          end
        end


  Principle: "control time and chance".

  Random data makes a test pass on most runs and fail on the one where the
  numbers line up badly, and nobody can reproduce that run: the values are
  gone. StreamData generators and `property` tests draw from the seed ExUnit
  prints, so `mix test --seed 123` brings the same data back. A fixed value
  in a plain `test` brings it back too.

  The check reports, in `:included_paths` (by default `*_test.exs` files and
  `test/support/`), a call to:

  - `:rand.uniform`, `:rand.uniform_real`, `:rand.normal` and `:rand.bytes`,
    which read the process's own random state;
  - `Enum.random`, `Enum.shuffle` and `Enum.take_random`.

  It does not report:

  - code inside a `property`, a `check all` or a `gen all` block, or inside
    an argument of a `StreamData` function, because ExUnit's seed drives
    them;
  - the `_s` functions of `:rand` (`:rand.uniform_s/1`, `:rand.normal_s/1`),
    `:rand.seed` and `:rand.seed_s`, which take or set an explicit state, so
    `:rand.seed_s(:exsss, ExUnit.configuration()[:seed])` followed by
    `:rand.uniform_s(state)` is a repeatable way to draw numbers;
  - `System.unique_integer`, `:erlang.unique_integer` and `make_ref`. They
    give a value that is unique, not random, and are how tests name processes,
    tables, emails and slugs without clashing. A test only turns flaky when
    the value itself matters, such as being sorted or validated as a
    positive number, and that cannot be told from the syntax. Add
    `{System, [:unique_integer]}` to `:functions` to report it as well.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoUnseededRandomness,
           [
             included_paths: [~r"_test\\.exs$", "test/support/"],
             excluded_paths: ["test/support/chaos.ex"],
             functions: [{Enum, [:random, :shuffle, :take_random]}, {System, [:unique_integer]}]
           ]}
        ]
      }
    ]
  }
  ```

  - `:included_paths` - Path substrings or regexes of the files to check.
    Defaults to `[~r"_test\\.exs$", "test/support/"]`.
  - `:excluded_paths` - Path substrings or regexes of files to skip, even
    inside `:included_paths`. Defaults to `[]`.
  - `:functions` - `{module, functions}` pairs that count as unseeded
    randomness. Defaults to the list above; list them again when you add
    your own.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoUnseededRandomness, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    tags: [:testing],
    param_defaults: [
      included_paths: [~r"_test\.exs$", "test/support/"],
      excluded_paths: [],
      functions: [
        {:rand, [:uniform, :uniform_real, :normal, :bytes]},
        {Enum, [:random, :shuffle, :take_random]}
      ]
    ],
    explanations: [
      check: @moduledoc,
      params: [
        included_paths: "Path substrings or regexes of the files to check.",
        excluded_paths: "Path substrings or regexes of files to skip.",
        functions: "`{module, functions}` pairs that count as unseeded randomness."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @seeded_blocks [:property, :check, :gen]
  @seeded_modules ["StreamData", "ExUnitProperties"]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    included_paths = Params.get(params, :included_paths, __MODULE__)
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if RemoteCalls.matches_path?(source_file.filename, included_paths) and
         not RemoteCalls.matches_path?(source_file.filename, excluded_paths) do
      issues(source_file, params)
    else
      []
    end
  end

  defp issues(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = Credo.SourceFile.ast(source_file)
    aliases = RemoteCalls.aliases(ast)
    functions = random_functions(params)

    ast
    |> Macro.prewalk([], fn node, acc ->
      if seeded?(node, aliases) do
        {nil, acc}
      else
        {node, random_call(node, aliases, functions) ++ acc}
      end
    end)
    |> elem(1)
    |> Enum.sort()
    |> Enum.map(fn {line, trigger} -> issue_for(issue_meta, line, trigger) end)
  end

  defp random_functions(params) do
    for {module, functions} <- Params.get(params, :functions, __MODULE__),
        function <- functions,
        into: MapSet.new(),
        do: {RemoteCalls.module_name(module), function}
  end

  defp seeded?({block, _meta, args}, _aliases) when block in @seeded_blocks and is_list(args) do
    block == :property or match?([{:all, _all_meta, _all_args} | _rest], args)
  end

  defp seeded?({{:., _dot_meta, [module_ast, _function]}, _meta, args}, aliases)
       when is_list(args) do
    RemoteCalls.resolve(module_ast, aliases) in @seeded_modules
  end

  defp seeded?(_node, _aliases), do: false

  defp random_call({{:., _dot_meta, [module_ast, function]}, meta, args}, aliases, functions)
       when is_atom(function) and is_list(args) do
    module = RemoteCalls.resolve(module_ast, aliases)

    if {module, function} in functions do
      [{meta[:line] || 0, "#{module}.#{function}"}]
    else
      []
    end
  end

  defp random_call(_node, _aliases, _functions), do: []

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Control time and chance: avoid `#{trigger}` in tests - the data differs on every run and a failure cannot be repeated. " <>
          "Use a fixed value, or draw it from a StreamData generator in a property test so ExUnit's seed brings it back.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
