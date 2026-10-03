defmodule Bylaw.Contract.ContractHelper do
  @moduledoc false

  alias Bylaw.Contract.Report

  @doc false
  @spec missed(report :: Report.t(), module :: module(), kind :: atom()) :: list(term())
  def missed(report, module, kind) do
    report
    |> Report.missed()
    |> Enum.filter(&(&1.module == module and &1.kind == kind))
    |> Enum.map(&detail/1)
    |> Enum.sort()
  end

  @doc false
  @spec property(report :: Report.t(), module :: module(), kind :: atom(), detail :: term()) ::
          Bylaw.Contract.Property.t()
  def property(report, module, kind, detail) do
    Enum.find(
      report.properties,
      &(&1.module == module and &1.kind == kind and detail(&1) == detail)
    )
  end

  defp detail(%{kind: kind} = property) when kind in [:clause, :guard_rejection],
    do: {property.function, property.arity, property.clause}

  defp detail(property), do: property.label
end
