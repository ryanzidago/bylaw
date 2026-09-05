defmodule Bylaw.Contract.CompilerUnassessableReasonsTest do
  use ExUnit.Case

  alias Bylaw.Contract.Check.ElixirCompiler
  alias Bylaw.Contract.CompilerInference
  alias Bylaw.Contract.CompilerInference.Elixir120
  alias Bylaw.Contract.TestFixtures.CompilerDeterministicTarget
  alias Module.Types.Descr

  test "an uncalled instrumented function is unassessable without a module warning" do
    {:ok, tracer} = Bylaw.Contract.start([CompilerDeterministicTarget], checks: [ElixirCompiler])
    coverage = Bylaw.Contract.stop(tracer)
    summary = Bylaw.Contract.summary(coverage)

    assert Enum.all?(coverage.compiler_return_alternatives, & &1.supported?)
    assert Enum.all?(coverage.compiler_return_alternatives, & &1.inferable?)
    assert MapSet.size(coverage.unknown) == 2
    assert summary.supported_compiler_return_alternatives == 0
    assert summary.unsupported_compiler_return_alternatives == 2
    assert summary.missed_compiler_return_alternatives == 0
    assert summary.compiler_unsupported == 0
    assert summary.compiler_warnings == 0
  end

  test "missing object code contributes an unsupported module and no alternatives" do
    module = Module.concat(__MODULE__, "Memory#{System.unique_integer([:positive])}")
    Code.compile_string("defmodule #{inspect(module)} do\ndef choose, do: :left\nend")

    try do
      assert_unsupported(module, "compiled BEAM object code is unavailable")
    after
      :code.delete(module)
      :code.purge(module)
    end
  end

  test "a missing checker chunk contributes an unsupported module and no alternatives" do
    with_module(&List.keydelete(&1, ~c"ExCk", 0), fn module ->
      assert_unsupported(module, "could not read the BEAM checker chunk")
    end)
  end

  test "a corrupt checker chunk retains a safe decoding reason" do
    with_module(&List.keyreplace(&1, ~c"ExCk", 0, {~c"ExCk", <<0>>}), fn module ->
      assert_unsupported(module, "Elixir checker chunk was rejected by safe term decoding")
    end)
  end

  test "a malformed descriptor retains a decoder failure reason" do
    exports = [{{:choose, 1}, %{sig: {:infer, nil, [{[:invalid], :invalid}]}}}]
    checker = :erlang.term_to_binary({:elixir_checker_v8, %{exports: exports}})

    with_module(&List.keyreplace(&1, ~c"ExCk", 0, {~c"ExCk", checker}), fn module ->
      assert_unsupported(module, "could not decode Elixir checker version :elixir_checker_v8")
    end)
  end

  test "a sticky module retains an instrumentation failure warning" do
    with_module(&Function.identity/1, fn module ->
      true = :code.stick_mod(module)

      try do
        {:ok, tracer} = Bylaw.Contract.start([module], checks: [ElixirCompiler])
        assert module.choose(:left) == :left
        coverage = Bylaw.Contract.stop(tracer)
        assert [%{status: :supported}] = coverage.compiler_modules
        assert MapSet.size(coverage.unknown) == 2
        assert Enum.empty?(coverage.compiler_calls)

        assert Enum.any?(coverage.compiler_warnings, fn warning ->
                 warning =~ "compiler clause instrumentation unsupported" and
                   warning =~ "sticky_directory"
               end)
      after
        :code.unstick_mod(module)
      end
    end)
  end

  test "unsupported input shapes prevent otherwise finite return inference" do
    left = Descr.atom([:left])
    right = Descr.atom([:right])
    input = Descr.open_tuple([left])
    exports = [{{:choose, 1}, %{sig: {:infer, nil, [{[input], left}, {[input], right}]}}}]
    {:ok, decoded} = Elixir120.return_alternatives(__MODULE__, exports)

    assert length(decoded.return_alternatives) == 2
    assert Enum.all?(decoded.return_alternatives, & &1.supported?)
    assert Enum.all?(decoded.return_alternatives, & &1.runtime_safe?)
    refute Enum.any?(decoded.return_alternatives, & &1.inferable?)
    refute Enum.any?(decoded.inference_rules, & &1.arguments_supported?)
    assert Enum.all?(decoded.inference_rules, &(MapSet.size(&1.output_ids) == 1))
  end

  defp assert_unsupported(module, expected_reason) do
    loaded = CompilerInference.load([module])
    assert [%{status: :unsupported, reason: reason}] = loaded.modules
    assert reason =~ expected_reason
    assert Enum.empty?(loaded.return_alternatives)
    assert length(loaded.warnings) == 1
  end

  defp with_module(transform_chunks, assertion) do
    module = Module.concat(__MODULE__, "Disk#{System.unique_integer([:positive])}")
    directory = Path.join(System.tmp_dir!(), Atom.to_string(module))
    File.mkdir_p!(directory)
    previous_options = Code.compiler_options()

    try do
      Code.compiler_options(debug_info: true, infer_signatures: [:elixir])

      [{^module, binary}] =
        Code.compile_string("""
        defmodule #{inspect(module)} do
          def choose(:left), do: :left
          def choose(:right), do: :right
        end
        """)

      :code.delete(module)
      :code.purge(module)
      {:ok, ^module, chunks} = :beam_lib.all_chunks(binary)
      {:ok, binary} = :beam_lib.build_module(transform_chunks.(chunks))
      path = Path.join(directory, "#{module}.beam")
      File.write!(path, binary)
      true = :code.add_patha(String.to_charlist(directory))
      {:module, ^module} = :code.load_abs(String.to_charlist(Path.rootname(path)))
      assertion.(module)
    after
      Code.compiler_options(previous_options)
      :code.delete(module)
      :code.purge(module)
      :code.del_path(String.to_charlist(directory))
      File.rm_rf!(directory)
    end
  end
end
