defmodule Bylaw.Credo.Check.Elixir.FloatUsagePropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.Elixir.FloatUsage

  property "decimal string literals are not reported as float usage" do
    check all(digits <- string(?0..?9, min_length: 1, max_length: 40)) do
      """
      defmodule Example.Amount do
        def value, do: Decimal.new("#{digits}")
      end
      """
      |> to_source_file()
      |> run_check(FloatUsage)
      |> refute_issues()
    end
  end
end
