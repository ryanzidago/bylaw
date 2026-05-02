defmodule Bylaw.Credo.Check.Warning.PreferDateTimeOverDateTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Warning.PreferDateTimeOverDate

  test "reports :date fields inside schemas" do
    """
    defmodule Example.Schema do
      use Ecto.Schema

      schema "events" do
        field :starts_at, :date
      end

      embedded_schema do
        field :ends_at, :date
      end
    end
    """
    |> to_source_file("lib/example/schema.ex")
    |> run_check(PreferDateTimeOverDate)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 5, trigger: "field", message: ~r/naive_datetime/},
      %{line_no: 9, trigger: "field", message: ~r/utc_datetime/}
    ])
  end

  test "reports :date columns inside migrations" do
    """
    defmodule Example.Repo.Migrations.AddEventDates do
      use Ecto.Migration

      def change do
        alter table(:events) do
          add :starts_at, :date
          add_if_not_exists :published_at, :date
          modify :ends_at, :date
        end
      end
    end
    """
    |> to_source_file("priv/repo/migrations/20260329120000_add_event_dates.exs")
    |> run_check(PreferDateTimeOverDate)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 6, trigger: "add", message: ~r/naive_datetime/},
      %{line_no: 7, trigger: "add_if_not_exists", message: ~r/utc_datetime/},
      %{line_no: 8, trigger: "modify", message: ~r/naive_datetime/}
    ])
  end

  test "does not report datetime fields or unrelated uses of :date" do
    """
    defmodule Example.Schema do
      use Ecto.Schema

      @default_type :date

      schema "events" do
        field :starts_at, :naive_datetime
        field :published_at, :utc_datetime
      end

      def default_type, do: @default_type
    end
    """
    |> to_source_file("lib/example/schema.ex")
    |> run_check(PreferDateTimeOverDate)
    |> refute_issues()
  end

  test "does not treat non-migration files as migrations" do
    """
    defmodule Example.Builder do
      def add(column, type), do: {column, type}

      def build do
        add(:starts_at, :date)
      end
    end
    """
    |> to_source_file("lib/example/builder.ex")
    |> run_check(PreferDateTimeOverDate)
    |> refute_issues()
  end
end
