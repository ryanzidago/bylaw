defmodule Bylaw.Contract.CompilerCapAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.Check.ElixirCompiler

  @first_ten [:f01, :f02, :f03, :f04, :f05, :f06, :f07, :f08, :f09, :f10]
  @all_functions @first_ten ++ [:f11, :f12, :f13, :f14]

  defmodule Generated do
    defmacro define do
      quote do
        def a_generated(:seen), do: :seen
        def a_generated(:other), do: :other
      end
    end
  end

  test "the default cap selects ten authored functions before observing any calls" do
    with_fixture(@all_functions, fn module ->
      {:ok, state, _} = ElixirCompiler.init([module], [], %{claims: MapSet.new()})

      try do
        assert selected(state) == @first_ten
        assert length(state.compiler_return_alternatives) == 28

        assert functions_with_ids(state.compiler_return_alternatives, state.unknown) ==
                 [:f11, :f12, :f13, :f14]

        assert state.compiler_warnings ==
                 [
                   "compiler clause instrumentation reached max_functions=10; 8 alternatives are unassessable"
                 ]

        before_calls = ElixirCompiler.coverage(state)
        assert MapSet.size(before_calls.unknown) == 28
        assert before_calls.compiler_calls == %{}
        assert before_calls.hits == %{}
      after
        ElixirCompiler.terminate(state)
      end
    end)
  end

  test "a bounded larger cap exposes called omissions while uncalled selections remain unknown" do
    with_fixture(@all_functions, fn module ->
      for {cap, observed} <- [{10, [:f01]}, {12, [:f01, :f11, :f12]}] do
        {:ok, tracer} = Contract.start([module], checks: [{ElixirCompiler, max_functions: cap}])

        coverage =
          try do
            for function <- [:f01, :f11, :f12, :f14],
                do: assert(apply(module, function, [:seen]) == :seen)

            Contract.stop(tracer)
          after
            if Process.alive?(tracer), do: Contract.stop(tracer)
          end

        assert coverage.compiler_calls == Map.new(observed, &{{module, &1, 1}, 1})

        assessable =
          Enum.reject(
            coverage.compiler_return_alternatives,
            &MapSet.member?(coverage.unknown, &1.id)
          )

        assert Enum.map(assessable, & &1.function) |> Enum.uniq() == observed
        assert length(assessable) == 2 * length(observed)
        assert MapSet.size(coverage.unknown) == 28 - 2 * length(observed)

        assert Map.take(Contract.summary(coverage), [
                 :observed_compiler_return_alternatives,
                 :missed_compiler_return_alternatives
               ]) ==
                 %{
                   observed_compiler_return_alternatives: length(observed),
                   missed_compiler_return_alternatives: length(observed)
                 }
      end
    end)
  end

  test "selection is independent of declaration order and excludes generated definitions" do
    cases = [
      {[:f14, :f03, :f01], [:f01, :f03, :f14]},
      {Enum.reverse(@first_ten), @first_ten},
      {Enum.reverse(@all_functions), @first_ten}
    ]

    for {declared, expected} <- cases do
      with_fixture(declared, fn module ->
        {:ok, state, _} = ElixirCompiler.init([module], [], %{claims: MapSet.new()})

        try do
          assert selected(state) == expected
          refute Enum.any?(state.compiler_return_alternatives, &(&1.function == :a_generated))
          assert module.a_generated(:seen) == :seen
          assert ElixirCompiler.coverage(state).compiler_calls == %{}
          assert length(state.compiler_return_alternatives) == 2 * length(declared)
        after
          ElixirCompiler.terminate(state)
        end
      end)
    end
  end

  defp selected(state),
    do: state.alternatives_by_mfa |> Map.keys() |> Enum.map(&elem(&1, 1)) |> Enum.sort()

  defp functions_with_ids(alternatives, ids) do
    alternatives
    |> Enum.filter(&MapSet.member?(ids, &1.id))
    |> Enum.map(& &1.function)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp with_fixture(functions, assertion) do
    module = Module.concat(__MODULE__, "Fixture#{System.unique_integer([:positive])}")
    directory = Path.join(System.tmp_dir!(), Atom.to_string(module))
    File.mkdir_p!(directory)

    definitions =
      Enum.map_join(functions, "\n", fn function ->
        "def #{function}(:seen), do: :seen\ndef #{function}(:other), do: :other"
      end)

    source = """
    defmodule #{inspect(module)} do
      require #{inspect(Generated)}
      #{inspect(Generated)}.define()
      #{definitions}
    end
    """

    previous_options = Code.compiler_options()

    binary =
      try do
        Code.compiler_options(debug_info: true, infer_signatures: [:elixir])
        [{^module, binary}] = Code.compile_string(source)
        binary
      after
        Code.compiler_options(previous_options)
      end

    path = Path.join(directory, "#{module}.beam")
    File.write!(path, binary)
    :code.purge(module)
    :code.delete(module)
    Code.prepend_path(directory)
    {:module, ^module} = :code.load_abs(String.to_charlist(Path.rootname(path)))

    try do
      assertion.(module)
    after
      :code.purge(module)
      :code.delete(module)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end
  end
end
