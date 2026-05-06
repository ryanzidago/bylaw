defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullabilityIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports nullable foreign key columns from the fixture schema" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyNullability, schemas: [TestDatabase.schema()]}
             ])

    assert issue.meta.table == "nullable_orders"
    assert issue.meta.column == "user_id"
  end

  test "returns issue metadata for nullable foreign key columns" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyNullability,
                schemas: [TestDatabase.schema()], tables: ["nullable_orders"]}
             ])

    assert issue.message ==
             "expected foreign key nullable_orders_user_id_fkey on #{TestDatabase.schema()}.nullable_orders.user_id to be NOT NULL"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "nullable_orders"
    assert issue.meta.constraint == "nullable_orders_user_id_fkey"
    assert issue.meta.column == "user_id"
  end

  test "passes when scoped to non-null foreign keys" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ForeignKeyNullability,
                schemas: [TestDatabase.schema()], tables: ["events", "indexed_orders"]}
             ])
  end

  test "skips intentional nullable foreign key exceptions" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ForeignKeyNullability,
                schemas: [TestDatabase.schema()],
                except: [[table: "nullable_orders", column: "user_id"]]}
             ])
  end

  test "reports user schemas that start with pg but not pg underscore" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyNullability, schemas: [TestDatabase.pg_schema()]}
             ])

    assert issue.meta.schema == TestDatabase.pg_schema()
    assert issue.meta.table == "nullable_orders"
  end

  test "applies schema and table scope together" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               {ForeignKeyNullability,
                schemas: [TestDatabase.schema(), TestDatabase.pg_schema()],
                tables: ["nullable_orders"]}
             ])

    assert Enum.map(issues, &{&1.meta.schema, &1.meta.table, &1.meta.column}) == [
             {TestDatabase.schema(), "nullable_orders", "user_id"},
             {TestDatabase.pg_schema(), "nullable_orders", "user_id"}
           ]
  end

  defp target do
    TestDatabase.start_repo!()
    TestDatabase.reset_fixtures!()

    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    Postgres.target(repo: TestRepo)
  end
end
