defmodule Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexesIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports equivalent indexes from the fixture schema" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {DuplicateIndexes, rules: [where: [schemas: [TestDatabase.schema()]]]}
             ])

    assert issue.meta.table == "duplicate_indexes"

    assert issue.meta.indexes == [
             "duplicate_indexes_status_duplicate_idx",
             "duplicate_indexes_status_idx"
           ]
  end

  test "returns issue metadata for duplicate indexes" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {DuplicateIndexes,
                rules: [
                  where: [
                    schemas: [TestDatabase.schema()],
                    tables: ["duplicate_indexes"]
                  ]
                ]}
             ])

    assert issue.message ==
             "expected #{TestDatabase.schema()}.duplicate_indexes to have no duplicate indexes, found duplicate_indexes_status_duplicate_idx, duplicate_indexes_status_idx"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "duplicate_indexes"

    assert issue.meta.indexes == [
             "duplicate_indexes_status_duplicate_idx",
             "duplicate_indexes_status_idx"
           ]
  end

  test "passes when scoped to tables without duplicate indexes" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {DuplicateIndexes,
                rules: [
                  where: [
                    schemas: [TestDatabase.schema()],
                    tables: ["indexed_orders"]
                  ]
                ]}
             ])
  end

  test "reports user schemas that start with pg but not pg underscore" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {DuplicateIndexes, rules: [where: [schemas: [TestDatabase.pg_schema()]]]}
             ])

    assert issue.meta.schema == TestDatabase.pg_schema()
    assert issue.meta.table == "duplicate_indexes"
  end

  test "applies schema and table scope together" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               {DuplicateIndexes,
                rules: [
                  where: [
                    schemas: [TestDatabase.schema(), TestDatabase.pg_schema()],
                    tables: ["duplicate_indexes"]
                  ]
                ]}
             ])

    assert Enum.map(issues, &{&1.meta.schema, &1.meta.table}) == [
             {TestDatabase.schema(), "duplicate_indexes"},
             {TestDatabase.pg_schema(), "duplicate_indexes"}
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
