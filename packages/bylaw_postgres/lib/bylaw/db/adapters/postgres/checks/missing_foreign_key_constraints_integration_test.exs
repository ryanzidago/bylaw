defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraintsIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports foreign-key-shaped columns without constraints from the fixture schema" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {MissingForeignKeyConstraints, rules: [where: [schemas: [TestDatabase.schema()]]]}
             ])

    assert issue.meta.table == "orders"
    assert issue.meta.column == "account_id"
  end

  test "returns issue metadata for missing foreign key constraints" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {MissingForeignKeyConstraints,
                rules: [
                  where: [
                    schemas: [TestDatabase.schema()],
                    tables: ["orders"]
                  ]
                ]}
             ])

    assert issue.message ==
             "expected #{TestDatabase.schema()}.orders.account_id to declare a foreign key constraint"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "orders"
    assert issue.meta.column == "account_id"
  end

  test "passes when scoped to foreign-key-shaped columns with constraints" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {MissingForeignKeyConstraints,
                rules: [
                  where: [
                    schemas: [TestDatabase.schema()],
                    tables: ["events", "indexed_orders"]
                  ]
                ]}
             ])
  end

  test "ignores primary key columns that end in id" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {MissingForeignKeyConstraints,
                rules: [
                  where: [
                    schemas: [TestDatabase.schema()],
                    tables: ["accounts"]
                  ]
                ]}
             ])
  end

  test "reports user schemas that start with pg but not pg underscore" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {MissingForeignKeyConstraints,
                rules: [where: [schemas: [TestDatabase.pg_schema()]]]}
             ])

    assert issue.meta.schema == TestDatabase.pg_schema()
    assert issue.meta.column == "account_id"
  end

  test "applies schema and table scope together" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               {MissingForeignKeyConstraints,
                rules: [
                  where: [
                    schemas: [TestDatabase.schema(), TestDatabase.pg_schema()],
                    tables: ["orders"]
                  ]
                ]}
             ])

    assert Enum.map(issues, &{&1.meta.schema, &1.meta.table, &1.meta.column}) == [
             {TestDatabase.schema(), "orders", "account_id"},
             {TestDatabase.pg_schema(), "orders", "account_id"}
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
