defmodule BylawDiffScope.Runtime do
  @moduledoc false
  @checks [
    Bylaw.Contract.Check.Typespec,
    Bylaw.Contract.Check.FunctionClauses,
    Bylaw.Contract.Check.ElixirCompiler
  ]

  @doc false
  @spec options(:all | MapSet.t()) :: keyword()
  def options(:all), do: [checks: @checks]
  def options(selection), do: [checks: @checks, only: Enum.sort(selection)]
end
