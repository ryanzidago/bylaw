defmodule Bylaw.Contract.BaselineAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract.Baseline
  alias Bylaw.Contract.Property
  alias Bylaw.Contract.Report

  setup do
    path =
      Path.join(System.tmp_dir!(), "bylaw-baseline-#{System.unique_integer([:positive])}.txt")

    on_exit(fn -> File.rm(path) end)
    {:ok, path: path}
  end

  test "writes a baseline that suppresses exactly the findings it recorded", %{path: path} do
    known = property(:clause, :greet, clause: 3)
    :ok = Baseline.write(%Report{properties: [known]}, path)

    fresh = property(:clause, :greet, clause: 2)
    report = %Report{properties: [known, fresh]}

    {filtered, suppressed} = Baseline.apply(report, path)

    assert Enum.map(Report.missed(filtered), & &1.clause) == [2]
    assert suppressed == 1
  end

  test "ignores line numbers so a baseline survives edits above the finding", %{path: path} do
    :ok =
      Baseline.write(%Report{properties: [property(:clause, :greet, clause: 1, line: 10)]}, path)

    moved = %Report{properties: [property(:clause, :greet, clause: 1, line: 99)]}

    {filtered, 1} = Baseline.apply(moved, path)

    assert Report.missed(filtered) == []
  end

  test "keys spec findings by argument and label", %{path: path} do
    nil_class = property(:argument_class, :get, argument: 1, label: "nil")
    other = property(:argument_class, :get, argument: 1, label: "String.t()")
    :ok = Baseline.write(%Report{properties: [nil_class]}, path)

    {filtered, 1} = Baseline.apply(%Report{properties: [nil_class, other]}, path)

    assert Enum.map(Report.missed(filtered), & &1.label) == ["String.t()"]
  end

  test "treats a missing baseline file as empty", %{path: path} do
    report = %Report{properties: [property(:clause, :greet, clause: 1)]}

    assert {^report, 0} = Baseline.apply(report, path)
  end

  test "records only missed properties in a stable sorted order", %{path: path} do
    observed = %{property(:clause, :a, clause: 1) | status: :observed}

    :ok =
      Baseline.write(
        %Report{
          properties: [
            property(:clause, :z, clause: 1),
            observed,
            property(:clause, :b, clause: 1)
          ]
        },
        path
      )

    lines = path |> File.read!() |> String.split("\n", trim: true)

    assert length(lines) == 2
    assert lines == Enum.sort(lines)
  end

  defp property(kind, function, fields) do
    struct!(
      Property,
      [
        id: {kind, function, fields},
        kind: kind,
        module: Sample,
        function: function,
        arity: 1,
        file: "lib/sample.ex",
        line: 1,
        status: :missed
      ] ++ fields
    )
  end
end
