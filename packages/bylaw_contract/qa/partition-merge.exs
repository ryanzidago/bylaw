defmodule BylawPartitionMerge do
  @moduledoc false
  @counters [
    :hits,
    :calls,
    :return_events,
    :compiler_calls,
    :clause_outcomes,
    :unmatched_clause_calls,
    :arity_calls
  ]

  @doc false
  @spec fingerprint(term()) :: String.t()
  def fingerprint(term) do
    term
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
  end

  @doc false
  @spec target_fingerprint(map()) :: String.t()
  def target_fingerprint(coverage) do
    coverage
    |> Map.drop(@counters ++ [:unknown, :incomplete, :status])
    |> Map.update!(:checks, fn checks ->
      Map.new(checks, fn {check, data} ->
        {check, Map.drop(data, @counters ++ [:unknown, :incomplete, :status])}
      end)
    end)
    |> fingerprint()
  end

  @doc false
  @spec load_plan(Path.t()) :: {map(), list(map())}
  def load_plan(path) do
    plan = path |> File.read!() |> JSON.decode!()

    snapshots =
      Enum.map(plan["partitions"], fn row ->
        if File.regular?(row["capture"]) and File.regular?(row["audit"]) do
          capture = row["capture"] |> File.read!() |> :erlang.binary_to_term()
          audit = row["audit"] |> File.read!() |> JSON.decode!()
          require_event = Enum.find(audit["events"], &(&1["name"] == "require_started"))

          Map.merge(capture, %{
            exit_code: row["exit_code"],
            cutoff: row["cutoff"],
            cleanup: audit["cleanup"]["clean"],
            required_files: require_event["details"]["paths"],
            capture_valid: true
          })
        else
          %{
            partition_id: row["partition_id"],
            exit_code: row["exit_code"],
            cutoff: row["cutoff"],
            cleanup: false,
            capture_valid: false,
            coverage: %{},
            test_states: %{}
          }
        end
      end)

    {plan, snapshots}
  end

  @doc false
  @spec merge(map(), list(map())) :: {:ok, map()} | {:error, map()}
  def merge(plan, snapshots) do
    ids = Enum.map(snapshots, & &1.partition_id)
    expected_ids = Enum.map(plan["partitions"], & &1["partition_id"])

    reason =
      cond do
        plan["schema"] != 1 or Enum.empty?(expected_ids) or
            Enum.sort(expected_ids) != Enum.to_list(1..length(expected_ids)) ->
          :incompatible_partition

        length(Enum.uniq(ids)) != length(ids) ->
          :duplicate_partition

        Enum.sort(ids) != Enum.sort(expected_ids) ->
          :missing_partition

        Enum.any?(snapshots, &native_failure?/1) ->
          :native_failure

        Enum.any?(snapshots, &(not complete?(&1.coverage))) ->
          :incomplete_partition

        Enum.any?(snapshots, &(not compatible?(plan, &1))) ->
          :incompatible_partition

        true ->
          nil
      end

    if reason do
      {:error, %{reason: reason, partitions: Enum.map(snapshots, &outcome/1)}}
    else
      [first | rest] = snapshots
      coverage = Enum.reduce(rest, first.coverage, &merge_coverage(&2, &1.coverage))
      {:ok, device} = StringIO.open("")
      Bylaw.Contract.Report.print(coverage, device, false)
      {:ok, {_, report}} = StringIO.close(device)

      {:ok,
       %{
         coverage: coverage,
         report_sha256: :crypto.hash(:sha256, report) |> Base.encode16(),
         test_states: Enum.reduce(snapshots, %{}, &sum_counters(&2, &1.test_states)),
         test_inventory: snapshots |> Enum.flat_map(& &1.test_inventory) |> Enum.sort(),
         bootstrap_calls: Enum.sum(Enum.map(snapshots, & &1.bootstrap_calls)),
         provenance:
           Enum.map(snapshots, &Map.take(&1, [:partition_id, :run_id, :source_fingerprint])),
         options: first.options,
         compiler_options: first.compiler_options
       }}
    end
  end

  defp native_failure?(snapshot) do
    snapshot.exit_code != 0 or snapshot.cutoff != nil or not snapshot.cleanup or
      not snapshot.capture_valid or Map.get(snapshot.test_states, :failed, 0) > 0 or
      Map.get(snapshot.test_states, :invalid, 0) > 0
  end

  defp complete?(coverage) do
    Map.get(coverage, :status, :complete) == :complete and
      Enum.empty?(Map.get(coverage, :incomplete, [])) and
      Enum.all?(Map.get(coverage, :checks, %{}), fn {_, check} ->
        Enum.empty?(Map.get(check, :incomplete, []))
      end)
  end

  defp compatible?(plan, snapshot) do
    expected = Enum.find(plan["partitions"], &(&1["partition_id"] == snapshot.partition_id))

    options =
      Map.new(snapshot.compiler_options, fn {key, value} -> {Atom.to_string(key), value} end)

    runtime = Map.new(snapshot.runtime, fn {key, value} -> {Atom.to_string(key), value} end)

    snapshot.schema == plan["schema"] and snapshot.run_id == plan["run_id"] and
      snapshot.source_fingerprint == plan["source_fingerprint"] and runtime == plan["runtime"] and
      snapshot.partition_total == length(plan["partitions"]) and
      snapshot.iterations == plan["iterations"] and snapshot.bootstrap_calls == plan["bootstrap"] and
      inspect(snapshot.options) == plan["options"] and options == plan["compiler_options"] and
      target_fingerprint(snapshot.coverage) == plan["target_fingerprint"] and
      Enum.sort(snapshot.required_files) == Enum.sort(expected["expected_files"]) and
      Enum.sort(snapshot.test_inventory) == Enum.sort(expected["expected_inventory"])
  end

  defp outcome(snapshot) do
    %{
      partition_id: snapshot.partition_id,
      exit_code: snapshot.exit_code,
      cutoff: snapshot.cutoff,
      incomplete: Map.get(snapshot.coverage, :incomplete, []),
      test_states: snapshot.test_states
    }
  end

  defp merge_coverage(left, right) do
    Map.new(left, fn
      {:checks, checks} ->
        {:checks,
         Map.new(checks, fn {check, data} ->
           {check, merge_coverage(data, Map.fetch!(right, :checks)[check])}
         end)}

      {:unknown, values} ->
        {:unknown, MapSet.union(values, right.unknown)}

      {key, counters} when key in @counters ->
        {key, sum_counters(counters, Map.fetch!(right, key))}

      {key, value} ->
        {key, value}
    end)
  end

  defp sum_counters(left, right) do
    Map.merge(left, right, fn
      _, a, b when is_map(a) and is_map(b) -> sum_counters(a, b)
      _, a, b when is_integer(a) and is_integer(b) and a >= 0 and b >= 0 -> a + b
    end)
  end
end
