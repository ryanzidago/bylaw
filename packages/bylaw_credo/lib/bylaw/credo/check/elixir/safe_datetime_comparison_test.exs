defmodule Bylaw.Credo.Check.Elixir.SafeDateTimeComparisonTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.SafeDateTimeComparison

  test "reports datetime field comparisons" do
    """
    defmodule Example do
      def run(entry) do
        entry.inserted_at == ~U[2026-01-26 10:00:00Z]
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> assert_issue(%{trigger: "=="})
  end

  test "reports date variable comparisons" do
    """
    defmodule Example do
      def run(start_date, end_date) do
        start_date <= end_date
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> assert_issue(%{trigger: "<="})
  end

  test "does not report Ecto where clauses" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query, inserted_at) do
        query
        |> where([r], r.inserted_at > ^inserted_at)
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report ordinary comparisons" do
    """
    defmodule Example do
      def run(a, b) do
        a == b
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end
end
