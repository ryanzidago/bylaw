defmodule Bylaw.Credo.Check.Elixir.SafeDateTimeComparisonTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.SafeDateTimeComparison

  test "reports comparisons against explicit datetime sigils" do
    source = """
    defmodule Example do
      def run(value) do
        value == ~U[2026-01-26 10:00:00Z]
        value == ~D[2026-01-26]
        value == ~N[2026-01-26 10:00:00]
        value == ~T[10:00:00]
      end
    end
    """

    issues =
      source
      |> to_source_file()
      |> run_check(SafeDateTimeComparison)

    assert length(issues) == 4
  end

  test "does not report comparisons between non-datetime literals" do
    """
    defmodule Example do
      def run do
        42 == 7
        "ready" == "done"
        {:ok, 42} == {:error, :invalid}
        [] == []
        %{state: :ready} == %{state: :done}
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end
end
