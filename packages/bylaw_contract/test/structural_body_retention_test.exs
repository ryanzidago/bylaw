defmodule Bylaw.Contract.StructuralBodyRetentionTest do
  use ExUnit.Case

  alias Bylaw.Contract.StructuralCoverage

  @moduletag :tmp_dir
  @fixture __MODULE__.Fixture

  setup context do
    Code.prepend_path(context.tmp_dir)

    on_exit(fn ->
      :code.purge(@fixture)
      :code.delete(@fixture)
      Code.delete_path(context.tmp_dir)
      File.rm_rf!(context.tmp_dir)
    end)

    :ok
  end

  test "retained classifier clauses discard original function bodies", context do
    loaded = load_fixture(context, 8)
    entries = classifier_clauses(loaded)
    assert length(entries) == 4

    for entry <- entries do
      assert {:clause, _, _, _, []} = entry.clause
    end
  end

  test "retained classifier plan size is independent of original body size", context do
    [first | rest] = Enum.map([8, 64, 512], &load_fixture(context, &1))

    for loaded <- rest do
      assert loaded == first

      assert :erts_debug.flat_size(loaded.classifiers) ==
               :erts_debug.flat_size(first.classifiers)
    end
  end

  test "compact plans preserve source metadata and never execute original bodies", context do
    loaded = load_fixture(context, 512)
    assert Enum.empty?(loaded.warnings)
    source_path = Path.expand("fixture.ex", context.tmp_dir)
    assert Enum.all?(loaded.clauses, &(&1.file == source_path))
    signal = Enum.filter(loaded.clauses, &(&1.function == :signal))
    assert Enum.map(signal, & &1.line) == [4, 5]
    assert Enum.map(signal, & &1.position) == [1, 2]

    assert Enum.map(signal, & &1.source) == [
             "def signal(pid, value) when pid == self()",
             "def signal(_, _)"
           ]

    original_md5 = @fixture.module_info(:md5)
    {:ok, shadow} = StructuralCoverage.start_shadow(loaded.classifiers)
    classifier = %{classifier_function: @fixture, source_function: :signal, source_arity: 2}

    try do
      assert StructuralCoverage.classify(shadow, classifier, [self(), :once], self()) ==
               {1, [{true, true}, {true, true}]}

      assert StructuralCoverage.classify(shadow, classifier, [nil, :once], self()) ==
               {2, [{true, false}, {true, true}]}

      refute_received {:original_body, _}
      assert apply(@fixture, :signal, [self(), :once]) == {:original_body, :once}
      assert_received {:original_body, :once}
      refute_received {:original_body, _}
      assert @fixture.module_info(:md5) == original_md5
    after
      StructuralCoverage.stop_shadow(shadow)
    end

    assert :code.is_loaded(shadow) == false
  end

  defp load_fixture(context, size) do
    path = Path.expand("fixture.ex", context.tmp_dir)
    beam_path = Path.join(context.tmp_dir, Atom.to_string(@fixture) <> ".beam")
    values = Enum.join(1..size, ", ")

    File.write!(path, """
    defmodule #{inspect(@fixture)} do
      def total(seed) when is_integer(seed), do: Enum.sum([#{values}]) + seed
      def total(:skip), do: 0
      def signal(pid, value) when pid == self(), do: send(pid, {:original_body, value})
      def signal(_, _), do: :other
    end
    """)

    :code.purge(@fixture)
    :code.delete(@fixture)
    File.rm(beam_path)
    options = Code.compiler_options()

    binary =
      try do
        Code.compiler_options(debug_info: true)
        [{@fixture, binary}] = Code.compile_file(path)
        binary
      after
        Code.compiler_options(options)
      end

    File.write!(beam_path, binary)
    assert apply(@fixture, :total, [3]) == div(size * (size + 1), 2) + 3
    assert apply(@fixture, :total, [:skip]) == 0
    loaded = StructuralCoverage.load([@fixture])
    assert Enum.empty?(loaded.warnings)
    loaded
  end

  defp classifier_clauses(loaded) do
    for classifier <- loaded.classifiers,
        mfa <- classifier.mfa_classifiers,
        clause <- mfa.clauses,
        do: clause
  end
end
