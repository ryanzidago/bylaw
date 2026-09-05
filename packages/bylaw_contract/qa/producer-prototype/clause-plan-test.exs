ExUnit.start()

defmodule ProducerClausePlanTest do
  use ExUnit.Case, async: false

  test "authored clause metadata generates exact native head guard rejection and selection counts" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "producer-clause-plan-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      :code.purge(ProducerClauseFixture)
      :code.delete(ProducerClauseFixture)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end)

    source = Path.join(directory, "fixture.ex")

    File.write!(source, """
    defmodule ProducerClauseFixture do
      def choose(value) when is_integer(value) and value > 0, do: :positive
      def choose(value) when is_integer(value), do: :integer
    end
    """)

    {:ok, _, _} =
      Kernel.ParallelCompiler.compile_to_path([source], directory, return_diagnostics: true)

    Code.prepend_path(directory)
    {:module, ProducerClauseFixture} = Code.ensure_loaded(ProducerClauseFixture)
    loaded = Bylaw.Contract.StructuralCoverage.load([ProducerClauseFixture])
    assert loaded.warnings == []
    [classifier] = loaded.classifiers
    [mfa_classifier] = classifier.mfa_classifiers
    assert length(mfa_classifier.clauses) == 2
    assert {:ok, plan} = ProducerClausePlan.compile(mfa_classifier)
    inputs = [1, -1, 0, :not_integer]
    baseline = Enum.map(inputs, &outcome/1)
    assert baseline == [:positive, :integer, :integer, :function_clause]
    {:ok, shadow} = Bylaw.Contract.StructuralCoverage.start_shadow(loaded.classifiers)

    descriptor = %{
      classifier_function: classifier.classifier_function,
      source_function: :choose,
      source_arity: 1
    }

    expected =
      try do
        Enum.map(
          inputs,
          &Bylaw.Contract.StructuralCoverage.classify(shadow, descriptor, [&1], self())
        )
      after
        Bylaw.Contract.StructuralCoverage.stop_shadow(shadow)
      end

    assert expected == [
             {1, [{true, true}, {true, true}]},
             {2, [{true, false}, {true, true}]},
             {2, [{true, false}, {true, true}]},
             {:no_clause, [{true, false}, {true, false}]}
           ]

    Task.async(fn -> :ok end) |> Task.await()

    for bits <- [16, 4096], {producers, pacing} <- [{1, :burst}, {8, :burst}, {8, :paced}] do
      big = Integer.pow(2, bits)
      values = [big, -big, 0, :not_integer]
      assert Enum.map(values, &outcome/1) == baseline
      resource = ProducerNative.new_slots(plan.slot_count)
      session = :trace.session_create(:producer_clause_plan, {ProducerNative, resource}, [])

      try do
        assert :trace.function(session, plan.mfa, plan.match_spec, [:local]) == 1
        ProducerNative.watch_code_changes(session)
        :trace.process(session, :all, true, [:call])

        tasks =
          for _ <- 1..producers do
            Task.async(fn ->
              for index <- 0..(div(8192, producers) - 1) do
                offset = rem(index, 4)
                assert outcome(Enum.at(values, offset)) == Enum.at(baseline, offset)
                if pacing == :paced and rem(index, 32) == 0, do: Process.sleep(1)
              end
            end)
          end

        Enum.each(tasks, &Task.await(&1, 15_000))
      after
        :trace.session_destroy(session)
      end

      assert ProducerNative.counts(resource) == {8192, 6144}
      assert ProducerNative.hits(resource) == [8192, 2048, 2048, 6144, 8192, 6144, 4096, 2048]

      assert ProducerNative.status(resource) == :complete,
             inspect(ProducerNative.reasons(resource))

      IO.puts(
        "clause-plan bits=#{bits} producers=#{producers} pacing=#{pacing} calls=8192 returns=6144 complete"
      )
    end

    assert map_size(plan.slots) == 8

    for {clause, index} <- Enum.with_index(mfa_classifier.clauses) do
      assert Map.fetch!(plan.slots, {clause.id, :head_matches}) == index * 4
      assert Map.fetch!(plan.slots, {clause.id, :selected}) == index * 4 + 2
    end
  end

  test "clause plans reject unsupported guards and excessive metadata" do
    clause = %{
      id: {ProducerClauseFixture, :choose, 1, 1, 1},
      clause:
        {:clause, 0, [{:var, 0, :value}],
         [[{:call, 0, {:atom, 0, :length}, [{:var, 0, :value}]}]], []}
    }

    metadata = %{mfa: {ProducerClauseFixture, :choose, 1}, clauses: [clause]}
    assert ProducerClausePlan.compile(metadata) == {:error, :unsupported_clause}

    oversized = %{
      clause
      | clause: {:clause, 0, [{:var, 0, :value}], [List.duplicate({:atom, 0, true}, 300)], []}
    }

    assert ProducerClausePlan.compile(%{metadata | clauses: [oversized]}) ==
             {:error, :unsupported_clause}

    literal_head = %{clause | clause: {:clause, 0, [{:tuple, 0, [{:atom, 0, :only}]}], [], []}}

    assert ProducerClausePlan.compile(%{metadata | clauses: [literal_head]}) ==
             {:error, :unsupported_clause}

    assert ProducerClausePlan.compile(%{metadata | clauses: List.duplicate(clause, 17)}) ==
             {:error, :clause_capacity}
  end

  test "clause plans preserve authored order and literal head outcomes" do
    mfa = {ProducerClauseFixture, :literal, 1}

    first = %{
      id: {ProducerClauseFixture, :literal, 1, 10, 1},
      clause: {:clause, 0, [{:atom, 0, :only}], [], []}
    }

    second = %{
      id: {ProducerClauseFixture, :literal, 1, 11, 2},
      clause: {:clause, 0, [{:var, 0, :value}], [], []}
    }

    assert {:ok, plan} = ProducerClausePlan.compile(%{mfa: mfa, clauses: [first, second]})
    assert {:ok, ^plan} = ProducerClausePlan.compile(%{mfa: mfa, clauses: [second, first]})

    assert {:ok, {true, true, true, false, true, true, false, false}, _, []} =
             :erlang.match_spec_test([:only], plan.match_spec, :trace)

    assert {:ok, {false, false, false, false, true, true, true, false}, _, []} =
             :erlang.match_spec_test([:other], plan.match_spec, :trace)

    integer = %{first | clause: {:clause, 0, [{:integer, 0, 7}], [], []}}
    {:ok, integer_plan} = ProducerClausePlan.compile(%{mfa: mfa, clauses: [integer, second]})

    assert {:ok, {true, true, true, false, true, true, false, false}, _, []} =
             :erlang.match_spec_test([7], integer_plan.match_spec, :trace)

    assert {:ok, {false, false, false, false, true, true, true, false}, _, []} =
             :erlang.match_spec_test([7.0], integer_plan.match_spec, :trace)
  end

  test "clause plans request enough bounded counters for three authored clauses" do
    mfa = {ProducerClauseFixture, :three, 1}

    clauses =
      for {pattern, position} <-
            Enum.with_index([{:atom, 0, :one}, {:atom, 0, :two}, {:var, 0, :value}], 1) do
        %{
          id: {ProducerClauseFixture, :three, 1, position, position},
          clause: {:clause, 0, [pattern], [], []}
        }
      end

    assert {:ok, plan} = ProducerClausePlan.compile(%{mfa: mfa, clauses: clauses})
    assert plan.slot_count == 12
    assert map_size(plan.slots) == 12

    assert {:ok, {false, false, false, false, true, true, true, false, true, true, false, false},
            _, []} =
             :erlang.match_spec_test([:two], plan.match_spec, :trace)
  end

  defp outcome(value) do
    apply(ProducerClauseFixture, :choose, [value])
  rescue
    FunctionClauseError -> :function_clause
  end
end
