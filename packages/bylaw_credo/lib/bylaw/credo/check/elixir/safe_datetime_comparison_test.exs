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

  test "reports datetime comparisons in piped Ecto or_where clauses" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query, cutoff_at) do
        query
        |> or_where([r], r.inserted_at > ^cutoff_at)
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> assert_issue(%{trigger: ">"})
  end

  test "reports datetime comparisons in piped Ecto join on clauses" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query, cutoff_at) do
        query
        |> join(:inner, [r], related in Related, on: related.inserted_at > ^cutoff_at)
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> assert_issue(%{trigger: ">"})
  end

  test "does not report multiline Ecto where keyword clauses" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query, period_start, period_end) do
        from(ba in query,
          where:
            ba.start_date <= ^period_end and
              (is_nil(ba.end_date) or ba.end_date >= ^period_start)
        )
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report comparisons anywhere inside an Ecto query" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query, cutoff_at) do
        from(ba in query,
          order_by: ba.start_date,
          select: ba.end_date >= ^cutoff_at
        )
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report comparisons in a keyword query using a schema source" do
    """
    defmodule Example do
      import Ecto.Query

      def run(period_start, period_end) do
        from(event in Event,
          where: event.starts_at <= ^period_end and event.ends_at >= ^period_start
        )
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report comparisons in a keyword query using a bare table name" do
    """
    defmodule Example do
      import Ecto.Query

      def run(cutoff_at) do
        from("events",
          where: event.starts_at < ^cutoff_at,
          select: event.ends_at >= ^cutoff_at
        )
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report comparisons in a composed pipe-based Ecto query" do
    """
    defmodule Example do
      import Ecto.Query

      def run(period_start, period_end) do
        from(event in Event, as: :event)
        |> join(:inner, [event: event], attendee in Attendee,
          on: attendee.event_id == event.id
        )
        |> where([event: event], event.starts_at <= ^period_end)
        |> where([event: event], is_nil(event.ends_at) or event.ends_at >= ^period_start)
        |> select([event: event], %{starts_at: event.starts_at})
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

  test "does not report non-datetime values returned by time-like functions" do
    """
    defmodule Example do
      def run do
        Clock.read_time() == {:ok, 42}
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report non-datetime values returned by time-like functions compared with variables" do
    """
    defmodule Example do
      def run(expected) do
        Clock.read_time() == expected
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report non-datetime values returned by date-like functions" do
    """
    defmodule Example do
      def run do
        Calendar.fetch_date() == {:ok, 42}
        Parser.parse_datetime() == {:error, :invalid}
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report non-datetime values returned by at-like functions" do
    """
    defmodule Example do
      def run(expected) do
        Repo.get_at() == expected
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report zero-arity field-like function results that are not datetimes" do
    """
    defmodule Example do
      def run(expected) do
        record.inserted_at() == expected
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end

  test "does not report datetime field checks against non-datetime literals" do
    """
    defmodule Example do
      def run(state) do
        state.turn_started_at != nil
        state.turn_first_token_at == nil
        state.turn_started_at == false
        state.turn_first_token_at == true
      end
    end
    """
    |> to_source_file()
    |> run_check(SafeDateTimeComparison)
    |> refute_issues()
  end
end
