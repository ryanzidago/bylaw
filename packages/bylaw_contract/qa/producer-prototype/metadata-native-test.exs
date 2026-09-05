ExUnit.start()

defmodule ProducerMetadataNativeTest do
  use ExUnit.Case, async: false

  test "persisted target metadata produces exact native counts across concurrent workload shapes" do
    directory =
      Path.join(
        System.tmp_dir!(),
        "producer-native-metadata-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    on_exit(fn ->
      :code.purge(ProducerMetadataFixture)
      :code.delete(ProducerMetadataFixture)
      Code.delete_path(directory)
      File.rm_rf!(directory)
    end)

    source = Path.join(directory, "fixture.ex")

    File.write!(source, """
    defmodule ProducerMetadataFixture do
      @spec echo(list(integer())) :: list(integer()) | :unused
      def echo(value), do: value
    end
    """)

    {:ok, _, _} =
      Kernel.ParallelCompiler.compile_to_path([source], directory, return_diagnostics: true)

    Code.prepend_path(directory)
    {:module, ProducerMetadataFixture} = Code.ensure_loaded(ProducerMetadataFixture)
    metadata = Bylaw.Contract.Specs.load([ProducerMetadataFixture])
    assert metadata.warnings == []
    assert metadata.boundaries == []

    entries =
      Enum.map(metadata.input_classes, &{:call, &1}) ++
        Enum.map(metadata.return_alternatives, &{:return, &1})

    assert length(entries) == 5
    {:ok, plan} = ProducerTargetPlan.compile(entries)

    for producers <- [1, 8], size <- [16, 256], pacing <- [:burst, :paced] do
      values = [[], [1], List.duplicate(Integer.pow(2, 100), size), :unused]

      expected =
        Map.new(entries, fn {_event, target} ->
          matches =
            Enum.count(
              values,
              &(Bylaw.Contract.TypeMatcher.match(&1, target.match_type) == :match)
            )

          {target.id, matches * 2048}
        end)

      assert Enum.sort(Map.values(expected)) == [2048, 2048, 2048, 2048, 6144]
      resource = ProducerNative.plan(plan.rules, 4096)
      session = :trace.session_create(:producer_metadata, {ProducerNative, resource}, [])

      try do
        for mfa <- plan.mfas do
          assert :trace.function(session, mfa, [{:_, [], [{:return_trace}]}], [:local]) == 1
        end

        ProducerNative.watch_code_changes(session)
        :trace.process(session, :all, true, [:call])

        tasks =
          for _ <- 1..producers do
            Task.async(fn ->
              for index <- 0..(div(8192, producers) - 1) do
                value = Enum.at(values, rem(index, 4))
                assert apply(ProducerMetadataFixture, :echo, [value]) == value
                if pacing == :paced and rem(index, 32) == 0, do: Process.sleep(1)
              end
            end)
          end

        Enum.each(tasks, &Task.await(&1, 15_000))
      after
        :trace.session_destroy(session)
      end

      assert ProducerNative.counts(resource) == {8192, 8192}
      hits = ProducerNative.hits(resource)
      actual = Map.new(plan.slots, fn {id, slot} -> {id, Enum.at(hits, slot)} end)
      assert actual == expected
      assert Enum.drop(hits, 5) == [0, 0, 0]

      assert ProducerNative.status(resource) == :complete,
             inspect(ProducerNative.reasons(resource))

      IO.puts(
        "metadata-native producers=#{producers} size=#{size} pacing=#{pacing} calls=8192 returns=8192 complete"
      )
    end
  end
end
