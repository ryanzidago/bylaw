defmodule Bylaw.Contract.Baseline do
  @moduledoc """
  A file of findings a team has reviewed and accepted, so the report shows only
  new ones.

  Many findings need a human to dismiss: a defensive clause, a `@spec` that is
  wider than the code, an input validated upstream. Record the current findings
  once, commit the file, and later runs print only what is not in it.

      ExUnit.start(
        formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter],
        bylaw_contract: [baseline: "test/bylaw_contract_baseline.txt"]
      )

  Run the suite with `BYLAW_CONTRACT_UPDATE_BASELINE=1` to rewrite the file from
  the findings of that run. The file holds one finding per line, keyed by
  function, kind, clause, argument and label, never by line number, so edits
  above a finding do not revive it. Delete a line to see a finding again.
  """

  alias Bylaw.Contract.Property
  alias Bylaw.Contract.Report

  @doc "Writes every missed property of the report to `path`, sorted, one per line."
  @spec write(report :: Report.t(), path :: Path.t()) :: :ok
  def write(%Report{} = report, path) do
    lines =
      report
      |> Report.missed()
      |> Enum.map(&key/1)
      |> Enum.uniq()
      |> Enum.sort()

    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, Enum.map_join(lines, "", &(&1 <> "\n")))
  end

  @doc """
  Removes the missed properties recorded in the baseline at `path` and returns
  the report with how many were removed. A missing file is an empty baseline.
  """
  @spec apply(report :: Report.t(), path :: Path.t()) :: {Report.t(), non_neg_integer()}
  def apply(%Report{} = report, path) do
    known = read(path)

    {suppressed, kept} =
      Enum.split_with(report.properties, &(&1.status == :missed and key(&1) in known))

    {%Report{report | properties: kept}, Enum.count(suppressed)}
  end

  defp read(path) do
    case File.read(path) do
      {:ok, content} -> content |> String.split("\n", trim: true) |> MapSet.new()
      {:error, _reason} -> MapSet.new()
    end
  end

  defp key(%Property{} = property) do
    [
      "#{inspect(property.module)}.#{property.function}/#{property.arity}",
      property.kind,
      property.clause,
      property.argument,
      property.label
    ]
    |> Enum.join("|")
    |> String.replace(~r/\s+/, " ")
  end
end
