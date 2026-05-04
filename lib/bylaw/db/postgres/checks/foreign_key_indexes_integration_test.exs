defmodule Bylaw.Db.Postgres.Checks.ForeignKeyIndexesIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.Checks.ForeignKeyIndexes
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports all foreign keys without supporting indexes from the fixture schema" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, schemas: [TestDatabase.schema()]}
             ])

    assert Enum.map(issues, & &1.meta.constraint) == [
             "included_events_account_fkey",
             "ordered_orders_user_id_fkey",
             "orders_user_id_fkey",
             "partial_orders_user_id_fkey"
           ]
  end

  test "returns issue metadata for missing foreign key indexes" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, schemas: [TestDatabase.schema()], tables: ["orders"]}
             ])

    assert issue.message ==
             "expected foreign key orders_user_id_fkey on #{TestDatabase.schema()}.orders to have a supporting index"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "orders"
    assert issue.meta.constraint == "orders_user_id_fkey"
    assert issue.meta.columns == ["user_id"]
  end

  test "passes when scoped to foreign keys with supporting indexes" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ForeignKeyIndexes,
                schemas: [TestDatabase.schema()], tables: ["events", "indexed_orders"]}
             ])
  end

  test "ignores partial indexes" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, schemas: [TestDatabase.schema()], tables: ["partial_orders"]}
             ])

    assert issue.meta.constraint == "partial_orders_user_id_fkey"
  end

  test "requires foreign key columns to be leading index columns" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, schemas: [TestDatabase.schema()], tables: ["ordered_orders"]}
             ])

    assert issue.meta.constraint == "ordered_orders_user_id_fkey"
  end

  test "ignores included columns for composite foreign key index coverage" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, schemas: [TestDatabase.schema()], tables: ["included_events"]}
             ])

    assert issue.meta.constraint == "included_events_account_fkey"
    assert issue.meta.columns == ["tenant_id", "account_id"]
  end

  test "reports user schemas that start with pg but not pg underscore" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, schemas: [TestDatabase.pg_schema()]}
             ])

    assert issue.meta.schema == TestDatabase.pg_schema()
    assert issue.meta.constraint == "orders_user_id_fkey"
  end

  test "applies schema and table scope together" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               {ForeignKeyIndexes,
                schemas: [TestDatabase.schema(), TestDatabase.pg_schema()], tables: ["orders"]}
             ])

    assert Enum.map(issues, &{&1.meta.schema, &1.meta.table}) == [
             {TestDatabase.schema(), "orders"},
             {TestDatabase.pg_schema(), "orders"}
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
