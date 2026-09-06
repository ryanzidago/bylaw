Code.require_file("partition-merge.exs", __DIR__)

defmodule BylawPartitionOracle do
  @moduledoc false
  @doc false
  @spec verify!(map(), list(integer()), non_neg_integer(), non_neg_integer()) :: :ok
  def verify!(coverage, members, iterations, bootstrap) do
    true = Map.get(coverage, :status, :complete) == :complete
    36 = length(coverage.input_classes)
    24 = length(coverage.return_alternatives)
    24 = length(coverage.arities)
    48 = length(coverage.clauses)
    true = Enum.empty?(coverage.boundaries)
    true = Enum.empty?(coverage.unknown)
    true = Enum.empty?(coverage.unmatched_clause_calls)

    for number <- 1..12 do
      module = Module.concat(BylawPhaseFixture, "Classifier#{number}")
      count = if number in members, do: iterations, else: 0
      extra = if number == 1, do: bootstrap, else: 0
      expected = 2 * count + extra
      ^expected = Map.get(coverage.calls, {module, :classify, 1}, 0)
      ^expected = Map.get(coverage.return_events, {module, :classify, 1}, 0)
      ^expected = Map.get(coverage.arity_calls, {module, :classify, 1}, 0)
      choices = 2 * count
      ^choices = Map.get(coverage.arity_calls, {module, :choose, 1}, 0)
    end

    for target <- coverage.input_classes ++ coverage.return_alternatives do
      number =
        target.module
        |> Atom.to_string()
        |> String.replace("Elixir.BylawPhaseFixture.Classifier", "")
        |> String.to_integer()

      count = if number in members, do: iterations, else: 0
      extra = if number == 1, do: bootstrap, else: 0

      expected =
        case target.label do
          label when label in ["positive", ":positive"] -> count + extra
          label when label in ["negative", ":nonpositive"] -> count
          "zero" -> 0
        end

      ^expected = Map.get(coverage.hits, target.id, 0)
    end

    for clause <- coverage.clauses do
      number =
        clause.module
        |> Atom.to_string()
        |> String.replace("Elixir.BylawPhaseFixture.Classifier", "")
        |> String.to_integer()

      count = if number in members, do: iterations, else: 0
      extra = if number == 1, do: bootstrap, else: 0

      expected =
        cond do
          clause.function == :choose ->
            %{selected: count, head_matches: count, guard_passes: count, guard_rejections: 0}

          clause.position == 1 ->
            %{
              selected: count + extra,
              head_matches: 2 * count + extra,
              guard_passes: count + extra,
              guard_rejections: count
            }

          true ->
            %{
              selected: count,
              head_matches: 2 * count + extra,
              guard_passes: 2 * count + extra,
              guard_rejections: 0
            }
        end

      ^expected =
        Map.get(coverage.clause_outcomes, clause.id, %{
          selected: 0,
          head_matches: 0,
          guard_passes: 0,
          guard_rejections: 0
        })
    end

    total = 2 * iterations * length(members) + bootstrap
    ^total = coverage.calls |> Map.values() |> Enum.sum()
    ^total = coverage.return_events |> Map.values() |> Enum.sum()
    total_arities = 4 * iterations * length(members) + bootstrap
    ^total_arities = coverage.arity_calls |> Map.values() |> Enum.sum()
    :ok
  end
end

[input_path, output_path, merged_path] = System.argv()
input = input_path |> File.read!() |> JSON.decode!()
reference = input["reference_capture"] |> File.read!() |> :erlang.binary_to_term()
reference_audit = input["reference_audit"] |> File.read!() |> JSON.decode!()

files =
  Enum.find(reference_audit["events"], &(&1["name"] == "require_started"))["details"]["paths"]
  |> Enum.sort()

partitions = length(input["commands"])

rows =
  Enum.map(input["commands"], fn row ->
    selected =
      for {file, index} <- Enum.with_index(files),
          rem(index, partitions) == row["partition_id"] - 1,
          do: file

    Map.merge(row, %{
      "expected_files" => selected,
      "expected_inventory" => Enum.filter(reference.test_inventory, &(hd(&1) in selected))
    })
  end)

plan =
  Map.merge(Map.take(input, ["run_id", "source_fingerprint", "iterations", "bootstrap"]), %{
    "schema" => 1,
    "runtime" => Map.new(reference.runtime, fn {key, value} -> {Atom.to_string(key), value} end),
    "partitions" => rows,
    "options" => inspect(reference.options),
    "compiler_options" =>
      Map.new(reference.compiler_options, fn {key, value} -> {Atom.to_string(key), value} end),
    "target_fingerprint" => BylawPartitionMerge.target_fingerprint(reference.coverage)
  })

plan_path = input["plan"]
File.write!(plan_path, JSON.encode!(plan))
{plan, snapshots} = BylawPartitionMerge.load_plan(plan_path)

if input["project"] == "fixture" do
  true = length(files) == 12
  true = length(reference.test_inventory) == 12

  for {snapshot, row} <- Enum.zip(snapshots, rows),
      snapshot.capture_valid,
      Map.get(snapshot.coverage, :status, :complete) == :complete do
    members =
      Enum.map(row["expected_files"], fn path ->
        [_, number] = Regex.run(~r/classifier_(\d+)_test.exs$/, path)
        String.to_integer(number)
      end)

    true = snapshot.test_states == %{passed: length(members)}

    :ok =
      BylawPartitionOracle.verify!(
        snapshot.coverage,
        members,
        input["iterations"],
        input["bootstrap"]
      )
  end
end

started = System.monotonic_time(:microsecond)
result = BylawPartitionMerge.merge(plan, snapshots)
merge_us = System.monotonic_time(:microsecond) - started

output =
  case result do
    {:ok, merged} ->
      if input["project"] == "fixture",
        do:
          BylawPartitionOracle.verify!(
            merged.coverage,
            Enum.to_list(1..12),
            input["iterations"],
            input["bootstrap"] * partitions
          )

      File.write!(merged_path, :erlang.term_to_binary(merged))

      %{
        accepted: true,
        coverage_sha256: BylawPartitionMerge.fingerprint(merged.coverage),
        report_sha256: merged.report_sha256,
        test_states: merged.test_states,
        bootstrap_calls: merged.bootstrap_calls
      }

    {:error, error} ->
      %{accepted: false, error: inspect(error, limit: :infinity, printable_limit: :infinity)}
  end

summaries =
  Enum.map(snapshots, fn snapshot ->
    if snapshot.capture_valid do
      %{
        partition_id: snapshot.partition_id,
        test_inventory: snapshot.test_inventory,
        test_states: snapshot.test_states,
        failures: inspect(snapshot.failures, limit: :infinity),
        init_us: snapshot.init_us,
        stop_us: snapshot.stop_us,
        compiler_options: snapshot.compiler_options,
        options: inspect(snapshot.options),
        coverage_status: Map.get(snapshot.coverage, :status, :complete),
        incomplete: inspect(Map.get(snapshot.coverage, :incomplete, []), limit: :infinity),
        coverage_sha256: BylawPartitionMerge.fingerprint(snapshot.coverage),
        target_fingerprint: BylawPartitionMerge.target_fingerprint(snapshot.coverage),
        report_sha256: snapshot.report_sha256,
        bootstrap_calls: snapshot.bootstrap_calls,
        calls: inspect(snapshot.coverage.calls, limit: :infinity),
        return_events: inspect(snapshot.coverage.return_events, limit: :infinity),
        arity_calls: inspect(snapshot.coverage.arity_calls, limit: :infinity)
      }
    else
      Map.take(snapshot, [:partition_id, :exit_code, :cutoff, :capture_valid])
    end
  end)

output = Map.merge(output, %{merge_us: merge_us, summaries: summaries})
File.write!(output_path, JSON.encode!(output))
