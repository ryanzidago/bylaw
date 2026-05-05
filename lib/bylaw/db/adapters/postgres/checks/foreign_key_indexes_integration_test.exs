defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyIndexesIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyIndexes
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports all foreign keys without supporting indexes from the fixture schema" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               ForeignKeyIndexes
             ])

    assert issues
           |> Enum.map(&{&1.meta.table, &1.meta.column})
           |> Enum.sort() == [
             {"accounts", "account_id"},
             {"included_events", "account_id"},
             {"ordered_orders", "user_id"},
             {"orders", "user_id"},
             {"partial_orders", "user_id"}
           ]
  end

  test "returns issue metadata for missing foreign key indexes" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, tables: ["orders"]}
             ])

    assert issue.message ==
             "expected foreign key-like column user_id on orders to have a supporting index"

    assert issue.meta.table == "orders"
    assert issue.meta.column == "user_id"
    assert issue.meta.columns == ["user_id"]
    assert issue.meta.source == :ecto_psql_extras
  end

  test "passes when scoped to foreign keys with supporting indexes" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ForeignKeyIndexes, tables: ["events", "indexed_orders"]}
             ])
  end

  test "ignores partial indexes" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, tables: ["partial_orders"]}
             ])

    assert issue.meta.table == "partial_orders"
    assert issue.meta.column == "user_id"
  end

  test "requires foreign key columns to be leading index columns" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, tables: ["ordered_orders"]}
             ])

    assert issue.meta.table == "ordered_orders"
    assert issue.meta.column == "user_id"
  end

  test "ignores included columns for foreign key-like index coverage" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, tables: ["included_events"]}
             ])

    assert issue.meta.table == "included_events"
    assert issue.meta.column == "account_id"
  end

  test "reports conventional foreign key-like columns even without outgoing constraints" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, tables: ["accounts"]}
             ])

    assert issue.meta.table == "accounts"
    assert issue.meta.column == "account_id"
  end

  test "deduplicates repeated table findings across schemas" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               {ForeignKeyIndexes, tables: ["orders"]}
             ])

    assert Enum.map(issues, &{&1.meta.table, &1.meta.column}) == [{"orders", "user_id"}]
  end

  defp target do
    TestDatabase.start_repo!()
    TestDatabase.reset_fixtures!()

    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    Postgres.target(repo: TestRepo)
  end
end
