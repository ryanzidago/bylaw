Code.require_file(Path.expand("../qa/partition-merge.exs", __DIR__))

defmodule Bylaw.Contract.PartitionObservationAcceptanceTest do
  use ExUnit.Case, async: true, group: :contract_qa_fixture

  setup_all do
    root = Path.join(System.tmp_dir!(), "bylaw-partitions-#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(root) end)
    assert File.regular?("qa/run-partition-observation.py")
    ordinary = run(root <> "/ordinary", 0, ["single", "sequential2", "concurrent2"])
    bootstrap = run(root <> "/bootstrap", 1, ["single", "sequential2"])
    %{ordinary: ordinary, bootstrap: bootstrap}
  end

  test "native partitions preserve the exact fixture inventory counters and rendered report",
       context do
    [single | partitions] = context.ordinary
    reference = capture(single)
    assert reference.test_states == %{passed: 12}

    for row <- partitions do
      merged = capture(row)
      assert merged.coverage == reference.coverage
      assert merged.report_sha256 == reference.report_sha256
      assert merged.test_states == %{passed: 12}
      {plan, snapshots} = BylawPartitionMerge.load_plan(row["plan"])
      assert length(snapshots) == 2
      assert Enum.all?(snapshots, &(map_size(&1.coverage.calls) == 6))
      assert Enum.all?(merged.coverage.calls, fn {_, count} -> count == 20 end)
      assert Enum.all?(merged.coverage.return_events, fn {_, count} -> count == 20 end)
      assert Enum.all?(merged.coverage.arity_calls, fn {_, count} -> count == 20 end)
      assert {:ok, reversed} = BylawPartitionMerge.merge(plan, Enum.reverse(snapshots))
      assert reversed.coverage == merged.coverage
      assert length(Enum.uniq(Enum.flat_map(snapshots, & &1.test_inventory))) == 12
    end
  end

  test "aggregation rejects missing duplicate and failed native partitions", context do
    {plan, [first, second]} = inputs(context)
    assert {:error, %{reason: :missing_partition}} = BylawPartitionMerge.merge(plan, [first])

    assert {:error, %{reason: :duplicate_partition}} =
             BylawPartitionMerge.merge(plan, [first, first])

    assert {:error, %{reason: :native_failure}} =
             BylawPartitionMerge.merge(plan, [first, %{second | exit_code: 1}])

    assert {:error, %{reason: :native_failure}} =
             BylawPartitionMerge.merge(plan, [first, %{second | cutoff: "deadline"}])
  end

  test "aggregation rejects incompatible schema code options targets and test inventories",
       context do
    {plan, [first, second]} = inputs(context)
    {ordinary_plan, _} = BylawPartitionMerge.load_plan(hd(context.ordinary)["plan"])
    {bootstrap_plan, _} = BylawPartitionMerge.load_plan(hd(context.bootstrap)["plan"])
    refute ordinary_plan["run_id"] == bootstrap_plan["run_id"]

    for changed <- [
          %{second | schema: 2},
          %{second | source_fingerprint: "different code"},
          %{second | options: Keyword.put(second.options, :seed, 7)},
          %{second | compiler_options: %{docs: true}},
          %{second | run_id: "another run"},
          Map.put(second, :runtime, %{elixir: "different", erts: "different"}),
          %{second | test_inventory: []},
          %{second | coverage: Map.put(second.coverage, :clauses, [])}
        ] do
      assert {:error, %{reason: :incompatible_partition}} =
               BylawPartitionMerge.merge(plan, [first, changed])
    end

    future_plan = Map.put(plan, "schema", 2)

    assert {:error, %{reason: :incompatible_partition}} =
             BylawPartitionMerge.merge(future_plan, [%{first | schema: 2}, %{second | schema: 2}])
  end

  test "aggregation retains incomplete reasons and refuses a complete report", context do
    {plan, [first, second]} = inputs(context)
    reasons = [%{reason: :trace_queue_limit, limit: 4096, observed: 4097}]
    incomplete = Map.merge(second.coverage, %{status: :incomplete, incomplete: reasons})

    assert {:error, result} =
             BylawPartitionMerge.merge(plan, [first, %{second | coverage: incomplete}])

    assert result.reason == :incomplete_partition
    assert Enum.find(result.partitions, &(&1.partition_id == 2)).incomplete == reasons
    refute Map.has_key?(result, :coverage)

    id = hd(first.coverage.input_classes).id
    unknown = MapSet.new([id])
    changed = put_in(first, [:coverage, :unknown], unknown)

    changed =
      put_in(changed, [:coverage, :checks, Bylaw.Contract.Check.Typespec, :unknown], unknown)

    assert {:ok, preserved} = BylawPartitionMerge.merge(plan, [changed, second])
    assert preserved.coverage.unknown == unknown
    assert preserved.coverage.checks[Bylaw.Contract.Check.Typespec].unknown == unknown
  end

  test "per VM bootstrap calls remain explicit when partition counters are summed", context do
    [single, partitioned] = Enum.map(context.bootstrap, &capture/1)
    mfa = {BylawPhaseFixture.Classifier1, :classify, 1}
    assert single.coverage.calls[mfa] == 21
    assert partitioned.coverage.calls[mfa] == 22
    assert single.bootstrap_calls == 1
    assert partitioned.bootstrap_calls == 2
    assert partitioned.test_states == single.test_states
    refute partitioned.coverage == single.coverage
  end

  test "concurrent partitions record total work and simultaneous process tree memory", context do
    row = Enum.find(context.ordinary, &(&1["layout"] == "concurrent2"))
    assert row["wall_s"] > 0
    assert row["cpu_s"] > 0

    assert row["sampled_group_peak_bytes"] >=
             Enum.max(Enum.map(row["commands"], & &1["sampled_tree_peak_bytes"]))

    assert row["cpu_s"] == Enum.sum(Enum.map(row["commands"], & &1["cpu_s"]))
    assert row["total_cpu_s"] > row["cpu_s"]
    assert row["merge"]["accepted"]
  end

  defp inputs(context) do
    context.ordinary
    |> Enum.find(&(&1["layout"] == "sequential2"))
    |> Map.fetch!("plan")
    |> BylawPartitionMerge.load_plan()
  end

  defp capture(row), do: row["merged_capture"] |> File.read!() |> :erlang.binary_to_term()

  defp run(output, bootstrap, layouts) do
    args = [
      "qa/run-partition-observation.py",
      "fixture",
      output,
      "--trials",
      "1",
      "--iterations",
      "10",
      "--bootstrap",
      Integer.to_string(bootstrap),
      "--layouts" | layouts
    ]

    {log, status} = System.cmd("python3", args, stderr_to_stdout: true)

    failures =
      if status != 0 do
        output |> Path.join("*/*.log") |> Path.wildcard() |> Enum.map_join("\n", &File.read!/1)
      else
        ""
      end

    assert status == 0, log <> failures
    output |> Path.join("results.json") |> File.read!() |> JSON.decode!()
  end
end
