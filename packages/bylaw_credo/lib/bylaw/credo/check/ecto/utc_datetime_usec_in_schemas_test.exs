defmodule Bylaw.Credo.Check.Ecto.UtcDatetimeUsecInSchemasTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.UtcDatetimeUsecInSchemas

  test "reports fields and timestamps of the wrong type in a schema" do
    issues =
      """
      defmodule Example.Order do
        use Ecto.Schema

        schema "orders" do
          field :a, :naive_datetime
          field :b, :naive_datetime_usec
          field :c, :utc_datetime
          field :d, {:array, :utc_datetime}
          field :e, :utc_datetime_usec
          timestamps(type: :utc_datetime)
        end
      end
      """
      |> to_source_file("lib/example/order.ex")
      |> run_check(UtcDatetimeUsecInSchemas)
      |> assert_issues(5)

    assert Enum.map(issues, & &1.line_no) == [5, 6, 7, 8, 10]
    assert Enum.at(issues, 0).message =~ ~r/Field `:a`.*use `:utc_datetime_usec`/
    assert Enum.at(issues, 3).message =~ "{:array, :utc_datetime}"
    assert Enum.at(issues, 4).trigger == "timestamps"
  end

  test "reports a bare timestamps and the inserted and updated options" do
    """
    defmodule Example.Order do
      use Ecto.Schema

      schema "orders" do
        timestamps()
      end
    end

    defmodule Example.Line do
      use Ecto.Schema

      schema "lines" do
        timestamps(inserted_at_type: :utc_datetime_usec, updated_at_type: :naive_datetime)
      end
    end
    """
    |> to_source_file("lib/example/order.ex")
    |> run_check(UtcDatetimeUsecInSchemas)
    |> assert_issues(2)
  end

  test "reports a wrong @timestamps_opts and allows a right one" do
    """
    defmodule Example.Order do
      use Ecto.Schema

      @timestamps_opts [type: :utc_datetime]

      schema "orders" do
        timestamps()
      end
    end
    """
    |> to_source_file("lib/example/order.ex")
    |> run_check(UtcDatetimeUsecInSchemas)
    |> assert_issues(1)
    |> assert_issues_match([%{line_no: 4, trigger: "@timestamps_opts"}])

    """
    defmodule Example.Order do
      use Ecto.Schema

      @timestamps_opts [type: :utc_datetime_usec]

      schema "orders" do
        timestamps()
      end
    end
    """
    |> to_source_file("lib/example/order.ex")
    |> run_check(UtcDatetimeUsecInSchemas)
    |> refute_issues()
  end

  test "allows utc_datetime_usec, dates, times and timestamps with the right type" do
    """
    defmodule Example.Order do
      use Ecto.Schema

      schema "orders" do
        field :a, :utc_datetime_usec
        field :b, :date
        field :c, :time
        field :d, :string, default: ":utc_datetime"
        field :e, Ecto.Enum, values: [:naive_datetime]
        timestamps(type: :utc_datetime_usec)
      end
    end
    """
    |> to_source_file("lib/example/order.ex")
    |> run_check(UtcDatetimeUsecInSchemas)
    |> refute_issues()
  end

  test "exempts embedded schemas and embeds blocks" do
    """
    defmodule Example.Form do
      use Ecto.Schema

      embedded_schema do
        field :goes_live, :naive_datetime
        timestamps()
      end
    end

    defmodule Example.Order do
      use Ecto.Schema

      @timestamps_opts [type: :utc_datetime_usec]

      schema "orders" do
        embeds_one :window, Window do
          field :starts, :naive_datetime
        end

        embeds_many :items, Item, primary_key: false do
          field :at, :utc_datetime
        end
      end
    end
    """
    |> to_source_file("lib/example/form.ex")
    |> run_check(UtcDatetimeUsecInSchemas)
    |> refute_issues()
  end

  test "precision :second requires utc_datetime" do
    issues =
      """
      defmodule Example.Order do
        use Ecto.Schema

        schema "orders" do
          field :a, :utc_datetime
          field :b, :utc_datetime_usec
          field :c, :naive_datetime
          timestamps(type: :utc_datetime)
        end
      end
      """
      |> to_source_file("lib/example/order.ex")
      |> run_check(UtcDatetimeUsecInSchemas, precision: :second)
      |> assert_issues(2)

    assert Enum.map(issues, & &1.line_no) == [6, 7]
    assert Enum.all?(issues, &(&1.message =~ "use `:utc_datetime`"))
  end

  test "allow_bare_timestamps allows timestamps without options" do
    """
    defmodule Example.Order do
      use MyApp.Schema

      schema "orders" do
        timestamps()
      end
    end
    """
    |> to_source_file("lib/example/order.ex")
    |> run_check(UtcDatetimeUsecInSchemas, allow_bare_timestamps: true)
    |> refute_issues()
  end

  test "ignores modules without a schema" do
    """
    defmodule Example.Types do
      @type t :: :naive_datetime
      def field(:naive_datetime), do: field(:a, :naive_datetime)
    end
    """
    |> to_source_file("lib/example/types.ex")
    |> run_check(UtcDatetimeUsecInSchemas)
    |> refute_issues()
  end
end
