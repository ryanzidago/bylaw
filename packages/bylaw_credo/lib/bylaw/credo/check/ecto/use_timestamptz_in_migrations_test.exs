defmodule Bylaw.Credo.Check.Ecto.UseTimestamptzInMigrationsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.UseTimestamptzInMigrations

  @path "priv/repo/migrations/20261201000000_example.exs"

  defp migration(body) do
    """
    defmodule Example.Repo.Migrations.Example do
      use Ecto.Migration

      def change do
    #{body}
      end
    end
    """
  end

  test "reports add, add_if_not_exists and modify with a zoneless type" do
    issues =
      """
          create table(:orders) do
            add :a, :utc_datetime_usec
            add :b, :utc_datetime
            add :c, :naive_datetime
            add :d, :naive_datetime_usec
            add :e, :timestamp, null: false
            add_if_not_exists :f, :utc_datetime_usec
            modify :g, :utc_datetime_usec, from: :timestamptz
            add :h, {:array, :utc_datetime}
          end
      """
      |> migration()
      |> to_source_file(@path)
      |> run_check(UseTimestamptzInMigrations)
      |> assert_issues(8)

    assert Enum.map(issues, & &1.line_no) == Enum.to_list(6..13)
    assert [%{trigger: "add", message: message} | _rest] = issues
    assert message =~ ~r/Column `:a`.*use `:timestamptz`/
    assert Enum.at(issues, 5).trigger == "add_if_not_exists"
    assert Enum.at(issues, 6).trigger == "modify"
    assert Enum.at(issues, 7).message =~ "{:array, :utc_datetime}"
  end

  test "reports timestamps with a zoneless type and bare timestamps" do
    issues =
      """
          create table(:orders) do
            timestamps(type: :utc_datetime_usec)
            timestamps(inserted_at_type: :timestamptz, updated_at_type: :naive_datetime)
            timestamps()
            timestamps
            timestamps(inserted_at: false)
          end
      """
      |> migration()
      |> to_source_file(@path)
      |> run_check(UseTimestamptzInMigrations)
      |> assert_issues(5)

    assert Enum.map(issues, & &1.line_no) == [6, 7, 8, 9, 10]
    assert Enum.at(issues, 0).message =~ "uses a type without a time zone"
    assert Enum.at(issues, 2).message =~ "without `type: :timestamptz`"
  end

  test "allows bare timestamps when configured" do
    """
        create table(:orders) do
          timestamps()
          timestamps(type: :utc_datetime_usec)
        end
    """
    |> migration()
    |> to_source_file(@path)
    |> run_check(UseTimestamptzInMigrations, allow_bare_timestamps: true)
    |> assert_issues(1)
  end

  test "allows timestamptz, dates, times and a conversion to timestamptz" do
    """
        create table(:orders) do
          add :a, :timestamptz
          add :b, :date
          add :c, :time
          add :d, :time_usec
          add :e, :string, default: ":utc_datetime"
          timestamps(type: :timestamptz)
          timestamps(inserted_at_type: :timestamptz, updated_at_type: :timestamptz)
        end

        alter table(:orders) do
          modify :f, :timestamptz, from: :utc_datetime_usec
          modify :g, :timestamptz, from: {:utc_datetime, [null: false]}
        end

        execute "COMMENT ON COLUMN orders.a IS 'a :utc_datetime value'"
    """
    |> migration()
    |> to_source_file(@path)
    |> run_check(UseTimestamptzInMigrations)
    |> refute_issues()
  end

  test "ignores files that are not migrations" do
    """
    defmodule Example.Builder do
      def build(table) do
        add(table, :a, :utc_datetime_usec)
        timestamps()
      end
    end
    """
    |> to_source_file("lib/example/builder.ex")
    |> run_check(UseTimestamptzInMigrations)
    |> refute_issues()
  end

  test "reports raw SQL that types a column or cast without a time zone" do
    issues =
      ~S'''
          execute "ALTER TABLE orders ADD COLUMN placed_at timestamp without time zone"
          execute("ALTER TABLE orders ADD COLUMN a timestamp NOT NULL", "SELECT 1")
          execute "UPDATE orders SET b = now()::timestamp"
          execute """
          CREATE TABLE t (
            id bigint,
            at TIMESTAMP(6)
          )
          """
          execute ~S"ALTER TABLE orders ALTER COLUMN c TYPE timestamp"
          execute "ALTER TABLE orders ADD COLUMN d TIMESTAMP WITHOUT TIME ZONE DEFAULT now()"
      '''
      |> migration()
      |> to_source_file(@path)
      |> run_check(UseTimestamptzInMigrations)
      |> assert_issues(6)

    assert Enum.map(issues, & &1.line_no) == [5, 6, 7, 8, 14, 15]
    assert Enum.all?(issues, &(&1.trigger == "execute"))
  end

  test "allows raw SQL with timestamptz and with the word in comments, strings or names" do
    ~S'''
        execute "ALTER TABLE orders ADD COLUMN a timestamp with time zone NOT NULL"
        execute "ALTER TABLE orders ADD COLUMN b timestamptz"
        execute "UPDATE orders SET c = now()::timestamp with time zone"
        execute "UPDATE orders SET d = 'timestamp without time zone'"
        execute "SELECT 1 -- a timestamp without time zone note"
        execute "SELECT to_timestamp(0), timestamp_col FROM t"
        execute "ALTER TABLE orders ADD COLUMN timestamp text"
        execute "/* a ::timestamp cast */ SELECT 1"
        execute unknown_sql()
        execute "SELECT '\#{interpolated}'"
    '''
    |> migration()
    |> to_source_file(@path)
    |> run_check(UseTimestamptzInMigrations)
    |> refute_issues()
  end

  test "skips excluded paths and migrations before the cut-off" do
    body = "    create table(:orders) do\n      add :a, :utc_datetime_usec\n    end"
    source = migration(body)

    source
    |> to_source_file("priv/repo/migrations/20261115100200_old.exs")
    |> run_check(UseTimestamptzInMigrations, excluded_paths: ["20261115100200_"])
    |> refute_issues()

    source
    |> to_source_file("priv/repo/migrations/20261115100200_old.exs")
    |> run_check(UseTimestamptzInMigrations, ignore_migrations_before: 20_261_201_000_000)
    |> refute_issues()

    source
    |> to_source_file(@path)
    |> run_check(UseTimestamptzInMigrations, ignore_migrations_before: 20_261_201_000_000)
    |> assert_issue()
  end

  test "forbidden_types can be narrowed" do
    "    add :a, :utc_datetime_usec\n    add :b, :naive_datetime"
    |> migration()
    |> to_source_file(@path)
    |> run_check(UseTimestamptzInMigrations, forbidden_types: [:naive_datetime])
    |> assert_issue(%{trigger: "add"})
  end
end
