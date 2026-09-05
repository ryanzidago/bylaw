defmodule Bylaw.Contract.StructuralEliminatedPrivateTest do
  use ExUnit.Case

  alias Bylaw.Contract.Check.FunctionClauses
  alias Bylaw.Contract.StructuralCoverage

  test "retains public clauses when an unused private function is eliminated" do
    with_fixture("defp unused(value), do: value", fn module ->
      loaded = StructuralCoverage.load([module])
      assert [%{status: :supported}] = loaded.modules
      assert length(loaded.clauses) == 2
      assert Enum.all?(loaded.clauses, &(&1.function == :keep))
      refute Enum.any?(loaded.arities, &(&1.function == :unused))
    end)
  end

  test "retains public clauses with eliminated private overrides with and without super" do
    for body <- ["super(value)", "value"] do
      with_fixture(override(body), fn module ->
        loaded = StructuralCoverage.load([module])
        assert [%{status: :supported}] = loaded.modules
        assert length(loaded.clauses) == 2
        assert Enum.all?(loaded.clauses, &(&1.function == :keep))
      end)
    end
  end

  test "preserves reachable private override obligations" do
    with_fixture(override("super(value)") <> "\ndef reach(value), do: unused(value)", fn module ->
      coverage = observe(module, fn -> assert module.reach(:value) == :value end)
      private = Enum.filter(coverage.clauses, &(&1.visibility == :private))
      assert Enum.any?(private)
      assert Enum.all?(private, &(coverage.clause_outcomes[&1.id].selected == 1))
    end)
  end

  test "surviving public obligations match a module without an unused private definition" do
    expected = with_fixture("", &public_obligations/1)
    actual = with_fixture("defp unused(value), do: value", &public_obligations/1)
    assert length(expected) == 2
    assert actual == expected
  end

  test "keeps missing public functions and incompatible debug metadata unassessable" do
    transforms = [
      {fn {:debug_info_v1, :elixir_erl, {:elixir_v1, metadata, options}} ->
         {:debug_info_v1, :elixir_erl,
          {:elixir_v1, %{metadata | unreachable: [keep: 1]}, options}}
       end, "keep/1 is absent"},
      {fn _ -> {:debug_info_v1, :elixir_erl, :incompatible} end,
       "Elixir debug information is unavailable or unsupported"},
      {fn {:debug_info_v1, :elixir_erl, {:elixir_v1, metadata, options}} ->
         {:debug_info_v1, :elixir_erl,
          {:elixir_v1, %{metadata | unreachable: :incompatible}, options}}
       end, "Elixir debug information is unavailable or unsupported"}
    ]

    for {transform, expected_reason} <- transforms do
      with_fixture(
        "",
        fn module ->
          loaded = StructuralCoverage.load([module])
          assert [%{status: :unsupported, reason: reason}] = loaded.modules
          assert reason =~ expected_reason
          assert Enum.empty?(loaded.clauses)
        end,
        &rewrite_debug(&1, transform)
      )
    end
  end

  test "observes both public clauses without reporting eliminated private code as missed" do
    with_fixture("defp unused(value), do: value", fn module ->
      coverage =
        observe(module, fn ->
          assert module.keep(:yes) == :accepted
          assert module.keep(:no) == :rejected
        end)

      assert length(coverage.clauses) == 2
      assert Enum.all?(coverage.clauses, &(coverage.clause_outcomes[&1.id].selected == 1))
      assert Enum.all?(coverage.arities, &(&1.function == :keep))
      {:ok, io} = StringIO.open("")
      Bylaw.Contract.print_report(coverage, io, colors: false)
      {_, output} = StringIO.contents(io)
      refute output =~ "unused"
      refute output =~ "Missed"
    end)
  end

  defp override(body),
    do: """
    defp unused(value), do: value
    defoverridable unused: 1
    defp unused(value), do: #{body}
    """

  defp public_obligations(module) do
    module
    |> then(&StructuralCoverage.load([&1]))
    |> Map.fetch!(:clauses)
    |> Enum.map(&Map.drop(&1, [:module, :id, :file]))
  end

  defp observe(module, function) do
    {:ok, tracer} = Bylaw.Contract.start([module], checks: [FunctionClauses])

    try do
      function.()
      Bylaw.Contract.stop(tracer)
    after
      if Process.alive?(tracer), do: Bylaw.Contract.stop(tracer)
    end
  end

  defp with_fixture(extra, assertion, transform \\ &Function.identity/1) do
    module = Module.concat(__MODULE__, "Fixture#{System.unique_integer([:positive])}")
    directory = Path.join(System.tmp_dir!(), Atom.to_string(module))
    File.mkdir_p!(directory)
    source = Path.join(directory, "fixture.ex")

    File.write!(source, """
    defmodule #{inspect(module)} do
      def keep(:yes), do: :accepted
      def keep(:no), do: :rejected
      #{extra}
    end
    """)

    previous_options = Code.compiler_options()

    [{^module, binary}] =
      try do
        Code.compiler_options(debug_info: true)
        Code.compile_file(source)
      after
        Code.compiler_options(previous_options)
      end

    :code.delete(module)
    :code.purge(module)
    File.write!(Path.join(directory, "#{module}.beam"), transform.(binary))
    Code.prepend_path(directory)
    {:module, ^module} = Code.ensure_loaded(module)

    try do
      assertion.(module)
    after
      :code.delete(module)
      :code.purge(module)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end
  end

  defp rewrite_debug(binary, transform) do
    {:ok, _, chunks} = :beam_lib.all_chunks(binary)

    chunks =
      Enum.map(chunks, fn
        {~c"Dbgi", debug} ->
          {~c"Dbgi",
           debug |> :erlang.binary_to_term() |> transform.() |> :erlang.term_to_binary()}

        chunk ->
          chunk
      end)

    {:ok, binary} = :beam_lib.build_module(chunks)
    binary
  end
end
