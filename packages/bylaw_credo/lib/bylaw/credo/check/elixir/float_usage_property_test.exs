defmodule Bylaw.Credo.Check.Elixir.FloatUsagePropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.Elixir.FloatUsage

  property "decimal string literals are not reported as float usage" do
    check all(
            whole <- string(?0..?9, min_length: 1, max_length: 20),
            fractional <- string(?0..?9, min_length: 1, max_length: 20),
            exponent <- integer(-100..100),
            format <- member_of([:integer, :negative, :decimal, :negative_decimal, :exponent])
          ) do
      decimal = decimal_string(format, whole, fractional, exponent)

      """
      defmodule Example.Amount do
        def value, do: Decimal.new("#{decimal}")
      end
      """
      |> to_source_file()
      |> run_check(FloatUsage)
      |> refute_issues()
    end
  end

  defp decimal_string(:integer, whole, _fractional, _exponent), do: whole
  defp decimal_string(:negative, whole, _fractional, _exponent), do: "-#{whole}"
  defp decimal_string(:decimal, whole, fractional, _exponent), do: "#{whole}.#{fractional}"

  defp decimal_string(:negative_decimal, whole, fractional, _exponent),
    do: "-#{whole}.#{fractional}"

  defp decimal_string(:exponent, whole, _fractional, exponent), do: "#{whole}e#{exponent}"
end
