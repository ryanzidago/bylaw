defmodule Bylaw.Contract.CompilerInferenceAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract.CompilerInference
  alias Bylaw.Contract.Check
  alias Bylaw.Contract.TestFixtures.CompilerDeterministicTarget
  alias Bylaw.Contract.TestFixtures.CompilerInferenceTarget
  alias Bylaw.Contract.TestFixtures.CompilerProtocolTarget
  alias Bylaw.Contract.TestFixtures.Registration

  defmodule GeneratedDefinition do
    defmacro define do
      quote do
        def generated(value), do: value
      end
    end
  end

  test "loads versioned compiler-inferred signatures from compiled modules" do
    loaded = CompilerInference.load([CompilerInferenceTarget])

    assert loaded.modules == [
             %{
               checker_version: :elixir_checker_v8,
               module: CompilerInferenceTarget,
               status: :supported
             }
           ]

    assert Enum.map(loaded.return_alternatives, & &1.label) == [
             ":accepted",
             "{:error, :rejected}"
           ]

    assert Enum.all?(loaded.return_alternatives, & &1.supported?)
    assert Enum.empty?(loaded.warnings)
  end

  test "infers an unambiguous return alternative from an observed call" do
    original_filename = :code.which(CompilerDeterministicTarget)

    {:ok, tracer} =
      Bylaw.Contract.start([CompilerDeterministicTarget], checks: [Check.ElixirCompiler])

    [worker] = :sys.get_state(tracer).workers
    runtime = :sys.get_state(worker).runtime
    mfa = {CompilerDeterministicTarget, :outcome, 1}

    assert Enum.empty?(runtime.calls)
    assert Enum.empty?(runtime.returns)
    assert :code.get_coverage_mode(CompilerDeterministicTarget) == :none
    assert Process.whereis(:cover_server) == nil
    assert :sys.get_state(worker).transport == :passive

    assert :code.which(CompilerDeterministicTarget) == ~c"bylaw-compiler-observer"

    assert in_new_process(fn -> CompilerDeterministicTarget.outcome(:accept) end) == :accepted

    coverage = Bylaw.Contract.stop(tracer)
    alternatives = Map.new(coverage.compiler_return_alternatives, &{&1.label, &1})

    assert coverage.compiler_calls == %{mfa => 1}
    assert Map.fetch!(coverage.hits, alternatives[":accepted"].id) == 1
    refute Map.has_key?(coverage.hits, alternatives["{:error, :rejected}"].id)
    assert CompilerDeterministicTarget.outcome(:reject) == {:error, :rejected}
    assert :code.get_coverage_mode(CompilerDeterministicTarget) == :none

    assert :code.which(CompilerDeterministicTarget) == original_filename
  end

  test "leaves compiler returns with ambiguous input to return inference unassessable" do
    {:ok, tracer} =
      Bylaw.Contract.start([CompilerInferenceTarget], checks: [Check.ElixirCompiler])

    assert in_new_process(fn -> CompilerInferenceTarget.outcome(true) end) == :accepted

    coverage = Bylaw.Contract.stop(tracer)

    assert Enum.empty?(coverage.hits)

    assert Enum.all?(coverage.compiler_return_alternatives, fn alternative ->
             MapSet.member?(coverage.unknown, alternative.id)
           end)
  end

  test "observes finite compiler-inferred return alternatives without a declared return union" do
    {:ok, tracer} =
      Bylaw.Contract.start([CompilerDeterministicTarget], checks: [Check.ElixirCompiler])

    assert in_new_process(fn -> CompilerDeterministicTarget.outcome(:accept) end) == :accepted

    coverage = Bylaw.Contract.stop(tracer)
    alternatives = Map.new(coverage.compiler_return_alternatives, &{&1.label, &1})

    assert Map.fetch!(coverage.hits, alternatives[":accepted"].id) == 1
    assert Map.get(coverage.hits, alternatives["{:error, :rejected}"].id, 0) == 0

    assert Map.take(Bylaw.Contract.summary(coverage), [
             :compiler_return_groups,
             :compiler_call_events,
             :compiler_return_alternatives,
             :observed_compiler_return_alternatives,
             :missed_compiler_return_alternatives,
             :compiler_unsupported
           ]) == %{
             compiler_return_groups: 1,
             compiler_call_events: 1,
             compiler_return_alternatives: 2,
             observed_compiler_return_alternatives: 1,
             missed_compiler_return_alternatives: 1,
             compiler_unsupported: 0
           }

    assert report(coverage) =~ "Bylaw.Contract compiler-inferred gaps"
    assert report(coverage) =~ "return: {:error, :rejected}"
  end

  test "keeps compiler-inferred obligations separate from typespec obligations" do
    {:ok, tracer} =
      Bylaw.Contract.start(
        [Registration],
        checks: [Check.Typespec, Check.ElixirCompiler]
      )

    coverage = Bylaw.Contract.stop(tracer)

    assert Enum.map(coverage.return_alternatives, & &1.label) == [
             "{:ok, Bylaw.Contract.TestFixtures.User.t()}",
             "{:error, :underage}"
           ]

    assert Enum.empty?(coverage.compiler_return_alternatives)
  end

  test "marks unavailable or incompatible compiler inference unsupported instead of missed" do
    with_compiled_module([debug_info: true, infer_signatures: false], fn module ->
      loaded = CompilerInference.load([module])

      assert Enum.empty?(loaded.return_alternatives)
      assert [%{module: ^module, status: :unsupported, reason: reason}] = loaded.modules
      assert reason =~ "inferred signatures are absent"
      assert [warning] = loaded.warnings
      assert warning =~ "compiler inference unsupported"
    end)

    with_compiled_module(
      [debug_info: true, infer_signatures: [:elixir]],
      &replace_checker_version(&1, :elixir_checker_future),
      fn module ->
        loaded = CompilerInference.load([module])

        assert Enum.empty?(loaded.return_alternatives)
        assert [%{module: ^module, status: :unsupported, reason: reason}] = loaded.modules
        assert reason == "unsupported Elixir checker version :elixir_checker_future"
      end
    )
  end

  test "reads compiler-inferred signatures without Elixir debug information" do
    with_compiled_module([debug_info: false, infer_signatures: [:elixir]], fn module ->
      loaded = CompilerInference.load([module])

      assert [%{module: ^module, status: :supported}] = loaded.modules
      assert Enum.map(loaded.return_alternatives, & &1.label) == [":left", ":right"]

      {:ok, tracer} =
        Bylaw.Contract.start([module], checks: [Check.ElixirCompiler])

      assert module.choose(true) == :left
      coverage = Bylaw.Contract.stop(tracer)

      assert Enum.empty?(coverage.compiler_calls)
      assert MapSet.size(coverage.unknown) == 2
      assert Enum.any?(coverage.compiler_warnings, &(&1 =~ "debug information is absent"))
    end)
  end

  test "compiler observation limits runtime obligations to authored functions" do
    with_compiled_generated_function_module(fn module ->
      {:ok, tracer} =
        Bylaw.Contract.start(
          [module],
          checks: [
            {Check.ElixirCompiler, max_functions: :infinity}
          ]
        )

      assert in_new_process(fn ->
               {
                 module.authored(:seen),
                 module.authored(:other),
                 module.generated(:seen)
               }
             end) == {:seen, :other, :seen}

      coverage = Bylaw.Contract.stop(tracer)

      assert Enum.map(coverage.compiler_return_alternatives, & &1.function) |> Enum.uniq() == [
               :authored
             ]

      assert Enum.empty?(coverage.unknown)
      assert coverage.compiler_calls == %{{module, :authored, 1} => 2}
    end)
  end

  test "compiler observation excludes protocol implementation modules" do
    implementation = List.Chars.impl_for(%CompilerProtocolTarget{})
    loaded = CompilerInference.load([implementation])

    assert [%{status: :supported}] = loaded.modules
    assert Enum.empty?(loaded.return_alternatives)
    assert Enum.empty?(loaded.authored_mfas)
  end

  test "compiler observation leaves open-ended structural returns unassessable" do
    with_compiled_open_ended_module(fn module ->
      {:ok, tracer} = Bylaw.Contract.start([module], checks: [Check.ElixirCompiler])

      assert in_new_process(fn -> module.choose([:item]) end) == [:item]
      coverage = Bylaw.Contract.stop(tracer)

      assert Enum.empty?(coverage.compiler_calls)

      assert Enum.all?(coverage.compiler_return_alternatives, fn alternative ->
               MapSet.member?(coverage.unknown, alternative.id)
             end)
    end)
  end

  test "compiler clause coverage includes locally dispatched function clauses" do
    with_compiled_local_call_module(fn module ->
      {:ok, tracer} = Bylaw.Contract.start([module], checks: [Check.ElixirCompiler])

      assert in_new_process(fn -> module.entry(:left) end) == :left
      coverage = Bylaw.Contract.stop(tracer)

      assert coverage.compiler_calls == %{{module, :choice, 1} => 1}

      entry_alternatives =
        Enum.filter(coverage.compiler_return_alternatives, &(&1.function == :entry))

      assert length(entry_alternatives) == 2
      assert Enum.all?(entry_alternatives, &MapSet.member?(coverage.unknown, &1.id))
      refute Enum.any?(entry_alternatives, &Map.has_key?(coverage.hits, &1.id))

      choice_alternatives =
        Enum.filter(coverage.compiler_return_alternatives, &(&1.function == :choice))

      left = Enum.find(choice_alternatives, &(&1.label == ":left"))
      right = Enum.find(choice_alternatives, &(&1.label == ":right"))

      assert Map.fetch!(coverage.hits, left.id) == 1
      refute Map.has_key?(coverage.hits, right.id)
    end)
  end

  test "compiler clause coverage counts calls regardless of the caller process" do
    {:ok, tracer} =
      Bylaw.Contract.start(
        [CompilerDeterministicTarget],
        checks: [Check.ElixirCompiler]
      )

    assert CompilerDeterministicTarget.outcome(:accept) == :accepted

    assert Task.async(fn -> CompilerDeterministicTarget.outcome(:reject) end)
           |> Task.await() == {:error, :rejected}

    coverage = Bylaw.Contract.stop(tracer)
    alternatives = Map.new(coverage.compiler_return_alternatives, &{&1.label, &1})

    assert coverage.compiler_calls == %{{CompilerDeterministicTarget, :outcome, 1} => 2}
    assert Map.fetch!(coverage.hits, alternatives[":accepted"].id) == 1
    assert Map.fetch!(coverage.hits, alternatives["{:error, :rejected}"].id) == 1
  end

  test "ExUnit compiler observation reports compiler clause counters" do
    source = """
    {:ok, _} = Application.ensure_all_started(:bylaw_contract)

    ExUnit.start(
      autorun: false,
      formatters: [Bylaw.Contract.ExUnitFormatter],
      bylaw_contract: [
        checks: [Bylaw.Contract.Check.ElixirCompiler]
      ]
    )

    defmodule Bylaw.Contract.TestFixtures.NestedCompilerObservationTest do
      use ExUnit.Case

      test "exercises compiler outcomes" do
        assert Bylaw.Contract.TestFixtures.CompilerDeterministicTarget.outcome(:accept) == :accepted

        assert Task.async(fn ->
                 Bylaw.Contract.TestFixtures.CompilerDeterministicTarget.outcome(:reject)
               end)
               |> Task.await() == {:error, :rejected}
      end
    end

    result = ExUnit.run()
    Process.sleep(100)
    IO.puts("nested_result=\#{result.total - result.failures}/\#{result.total}")
    """

    {output, 0} =
      System.cmd(
        System.find_executable("elixir"),
        ["-pa", Application.app_dir(:bylaw_contract, "ebin"), "-e", source],
        env: [
          {"BYLAW_CONTRACT_APPS", "bylaw_contract"},
          {"BYLAW_CONTRACT_REPORT", "summary"}
        ],
        stderr_to_stdout: true
      )

    assert output =~ "nested_result=1/1"
    assert output =~ "compiler_call_events=2 "
  end

  test "compiler clause counters handle high-volume calls without a trace backlog" do
    with_compiled_stress_module(fn module ->
      {:ok, tracer} =
        Bylaw.Contract.start(
          [module],
          checks: [Check.ElixirCompiler]
        )

      in_new_process(fn ->
        Enum.each(1..10_000, fn _ ->
          module.choose(:item)
        end)
      end)

      stop_task = Task.async(fn -> Bylaw.Contract.stop(tracer) end)

      case Task.yield(stop_task, 1_000) do
        {:ok, coverage} ->
          mfa = {module, :choose, 1}
          assert coverage.compiler_calls == %{mfa => 10_000}

          alternatives = Map.new(coverage.compiler_return_alternatives, &{&1.label, &1})
          assert Map.fetch!(coverage.hits, alternatives[":item"].id) == 1
          refute MapSet.member?(coverage.unknown, alternatives[":other"].id)

          assert report(coverage) =~ ":other"

          assert Map.take(Bylaw.Contract.summary(coverage), [
                   :observed_compiler_return_alternatives,
                   :missed_compiler_return_alternatives,
                   :unsupported_compiler_return_alternatives,
                   :compiler_warnings
                 ]) == %{
                   observed_compiler_return_alternatives: 1,
                   missed_compiler_return_alternatives: 1,
                   unsupported_compiler_return_alternatives: 0,
                   compiler_warnings: 0
                 }

        nil ->
          Task.shutdown(stop_task, :brutal_kill)
          Process.unlink(tracer)
          Process.exit(tracer, :kill)
          flunk("compiler call inference did not drain within 1 second")
      end
    end)
  end

  test "compiler call inference emits no runtime trace interests" do
    {:ok, tracer} =
      Bylaw.Contract.start([CompilerDeterministicTarget], checks: [Check.ElixirCompiler])

    [worker] = :sys.get_state(tracer).workers
    worker_state = :sys.get_state(worker)

    assert worker_state.transport == :passive
    assert worker_state.session == nil
    assert Enum.empty?(worker_state.runtime.calls)
    assert Enum.empty?(worker_state.runtime.returns)
    assert :code.get_coverage_mode(CompilerDeterministicTarget) == :none
    assert Process.whereis(:cover_server) == nil

    _coverage = Bylaw.Contract.stop(tracer)
  end

  test "compiler observation bounds the number of instrumented functions" do
    with_compiled_function_limit_module(fn module ->
      {:ok, tracer} =
        Bylaw.Contract.start(
          [module],
          checks: [{Check.ElixirCompiler, max_functions: 1}]
        )

      assert in_new_process(fn ->
               {
                 module.alpha(:seen),
                 module.alpha(:other),
                 module.omega(:seen)
               }
             end) == {:seen, :other, :seen}

      coverage = Bylaw.Contract.stop(tracer)

      assessable =
        Enum.reject(
          coverage.compiler_return_alternatives,
          &MapSet.member?(coverage.unknown, &1.id)
        )

      unassessable =
        Enum.filter(
          coverage.compiler_return_alternatives,
          &MapSet.member?(coverage.unknown, &1.id)
        )

      assert Enum.map(assessable, & &1.function) |> Enum.uniq() == [:alpha]
      assert Enum.map(unassessable, & &1.function) |> Enum.uniq() == [:omega]
      assert coverage.compiler_calls == %{{module, :alpha, 1} => 2}

      assert Map.take(Bylaw.Contract.summary(coverage), [
               :compiler_return_alternatives,
               :observed_compiler_return_alternatives,
               :missed_compiler_return_alternatives,
               :unsupported_compiler_return_alternatives
             ]) == %{
               compiler_return_alternatives: 4,
               observed_compiler_return_alternatives: 2,
               missed_compiler_return_alternatives: 0,
               unsupported_compiler_return_alternatives: 2
             }
    end)
  end

  defp with_compiled_module(compiler_options, assertion) do
    with_compiled_module(compiler_options, &Function.identity/1, assertion)
  end

  defp with_compiled_module(compiler_options, transform_binary, assertion) do
    module =
      Module.concat(Bylaw.Contract, "CompilerInference#{System.unique_integer([:positive])}")

    directory = Path.join(System.tmp_dir!(), Atom.to_string(module))
    File.mkdir_p!(directory)
    previous_options = Code.compiler_options()

    binary =
      try do
        Code.compiler_options(compiler_options)

        [{^module, binary}] =
          Code.compile_string("""
          defmodule #{inspect(module)} do
            def choose(true), do: :left
            def choose(false), do: :right
          end
          """)

        binary
      after
        Code.compiler_options(previous_options)
      end

    :code.delete(module)
    :code.purge(module)
    binary = transform_binary.(binary)
    beam_path = Path.join(directory, "#{module}.beam")
    File.write!(beam_path, binary)
    true = :code.add_patha(String.to_charlist(directory))
    {:module, ^module} = :code.load_abs(String.to_charlist(Path.rootname(beam_path)))

    try do
      assertion.(module)
    after
      :code.delete(module)
      :code.purge(module)
      :code.del_path(String.to_charlist(directory))
      File.rm_rf!(directory)
    end
  end

  defp replace_checker_version(binary, checker_version) do
    {:ok, _module, chunks} = :beam_lib.all_chunks(binary)

    chunks =
      Enum.map(chunks, fn
        {~c"ExCk", _chunk} ->
          {~c"ExCk", :erlang.term_to_binary({checker_version, %{exports: []}})}

        chunk ->
          chunk
      end)

    {:ok, binary} = :beam_lib.build_module(chunks)
    binary
  end

  defp with_compiled_stress_module(assertion) do
    module =
      Module.concat(Bylaw.Contract, "CompilerStress#{System.unique_integer([:positive])}")

    with_compiled_source(
      module,
      "def choose(:item), do: :item\ndef choose(:other), do: :other",
      &replace_checker_with_stress_signature/1,
      assertion
    )
  end

  defp with_compiled_open_ended_module(assertion) do
    module =
      Module.concat(Bylaw.Contract, "CompilerOpenEnded#{System.unique_integer([:positive])}")

    with_compiled_source(
      module,
      "def choose(value), do: value",
      &replace_checker_with_open_ended_signature/1,
      assertion
    )
  end

  defp with_compiled_function_limit_module(assertion) do
    module =
      Module.concat(Bylaw.Contract, "CompilerLimit#{System.unique_integer([:positive])}")

    with_compiled_source(
      module,
      """
      def alpha(:seen), do: :seen
      def alpha(:other), do: :other
      def omega(:seen), do: :seen
      def omega(:other), do: :other
      """,
      &replace_checker_with_function_limit_signatures/1,
      assertion
    )
  end

  defp with_compiled_generated_function_module(assertion) do
    module =
      Module.concat(Bylaw.Contract, "CompilerGenerated#{System.unique_integer([:positive])}")

    with_compiled_source(
      module,
      """
      require #{inspect(GeneratedDefinition)}
      #{inspect(GeneratedDefinition)}.define()
      def authored(:seen), do: :seen
      def authored(:other), do: :other
      """,
      &replace_checker_with_authorship_signatures/1,
      assertion
    )
  end

  defp with_compiled_local_call_module(assertion) do
    module = Module.concat(Bylaw.Contract, "CompilerLocal#{System.unique_integer([:positive])}")

    with_compiled_source(
      module,
      "def entry(value), do: choice(value)\ndef choice(:left), do: :left\ndef choice(:right), do: :right",
      &replace_checker_with_local_call_signatures/1,
      assertion
    )
  end

  defp with_compiled_source(module, source, transform_binary, assertion) do
    directory = Path.join(System.tmp_dir!(), Atom.to_string(module))
    File.mkdir_p!(directory)
    previous_options = Code.compiler_options()

    binary =
      try do
        Code.compiler_options(debug_info: true, infer_signatures: [:elixir])

        [{^module, binary}] =
          Code.compile_string("""
          defmodule #{inspect(module)} do
            #{source}
          end
          """)

        binary
      after
        Code.compiler_options(previous_options)
      end

    :code.delete(module)
    :code.purge(module)
    binary = transform_binary.(binary)
    beam_path = Path.join(directory, "#{module}.beam")
    File.write!(beam_path, binary)
    true = :code.add_patha(String.to_charlist(directory))
    {:module, ^module} = :code.load_abs(String.to_charlist(Path.rootname(beam_path)))

    try do
      assertion.(module)
    after
      :code.delete(module)
      :code.purge(module)
      :code.del_path(String.to_charlist(directory))
      File.rm_rf!(directory)
    end
  end

  defp replace_checker_with_stress_signature(binary) do
    alias Module.Types.Descr

    item_return = Descr.atom([:item])
    other_return = Descr.atom([:other])

    exports = [
      {{:choose, 1},
       %{sig: {:infer, nil, [{[item_return], item_return}, {[other_return], other_return}]}}}
    ]

    {:ok, _module, chunks} = :beam_lib.all_chunks(binary)

    chunks =
      Enum.map(chunks, fn
        {~c"ExCk", _chunk} ->
          {~c"ExCk", :erlang.term_to_binary({:elixir_checker_v8, %{exports: exports}})}

        chunk ->
          chunk
      end)

    {:ok, binary} = :beam_lib.build_module(chunks)
    binary
  end

  defp replace_checker_with_open_ended_signature(binary) do
    alias Module.Types.Descr

    list_return = Descr.non_empty_list(Descr.atom([:item]))
    other_return = Descr.atom([:other])

    exports = [
      {{:choose, 1},
       %{sig: {:infer, nil, [{[list_return], list_return}, {[other_return], other_return}]}}}
    ]

    {:ok, _module, chunks} = :beam_lib.all_chunks(binary)

    chunks =
      Enum.map(chunks, fn
        {~c"ExCk", _chunk} ->
          {~c"ExCk", :erlang.term_to_binary({:elixir_checker_v8, %{exports: exports}})}

        chunk ->
          chunk
      end)

    {:ok, binary} = :beam_lib.build_module(chunks)
    binary
  end

  defp replace_checker_with_function_limit_signatures(binary) do
    alias Module.Types.Descr

    seen_return = Descr.atom([:seen])
    other_return = Descr.atom([:other])

    signature =
      {:infer, nil, [{[seen_return], seen_return}, {[other_return], other_return}]}

    exports = [
      {{:alpha, 1}, %{sig: signature}},
      {{:omega, 1}, %{sig: signature}}
    ]

    {:ok, _module, chunks} = :beam_lib.all_chunks(binary)

    chunks =
      Enum.map(chunks, fn
        {~c"ExCk", _chunk} ->
          {~c"ExCk", :erlang.term_to_binary({:elixir_checker_v8, %{exports: exports}})}

        chunk ->
          chunk
      end)

    {:ok, binary} = :beam_lib.build_module(chunks)
    binary
  end

  defp replace_checker_with_authorship_signatures(binary) do
    alias Module.Types.Descr

    seen_return = Descr.atom([:seen])
    other_return = Descr.atom([:other])

    signature =
      {:infer, nil, [{[seen_return], seen_return}, {[other_return], other_return}]}

    exports = [
      {{:authored, 1}, %{sig: signature}},
      {{:generated, 1}, %{sig: signature}}
    ]

    {:ok, _module, chunks} = :beam_lib.all_chunks(binary)

    chunks =
      Enum.map(chunks, fn
        {~c"ExCk", _chunk} ->
          {~c"ExCk", :erlang.term_to_binary({:elixir_checker_v8, %{exports: exports}})}

        chunk ->
          chunk
      end)

    {:ok, binary} = :beam_lib.build_module(chunks)
    binary
  end

  defp replace_checker_with_local_call_signatures(binary) do
    alias Module.Types.Descr

    left_return = Descr.atom([:left])
    right_return = Descr.atom([:right])

    signature =
      {:infer, nil, [{[left_return], left_return}, {[right_return], right_return}]}

    exports = [
      {{:choice, 1}, %{sig: signature}},
      {{:entry, 1}, %{sig: signature}}
    ]

    {:ok, _module, chunks} = :beam_lib.all_chunks(binary)

    chunks =
      Enum.map(chunks, fn
        {~c"ExCk", _chunk} ->
          {~c"ExCk", :erlang.term_to_binary({:elixir_checker_v8, %{exports: exports}})}

        chunk ->
          chunk
      end)

    {:ok, binary} = :beam_lib.build_module(chunks)
    binary
  end

  defp report(coverage) do
    {:ok, device} = StringIO.open("")
    :ok = Bylaw.Contract.print_report(coverage, device, colors: false)
    {_, output} = StringIO.contents(device)
    output
  end

  defp in_new_process(function) do
    function
    |> Task.async()
    |> Task.await(:infinity)
  end
end
