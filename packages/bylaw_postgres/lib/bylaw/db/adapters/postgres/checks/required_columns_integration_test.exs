defmodule Bylaw.Db.Adapters.Postgres.Checks.RequiredColumnsIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports tables missing required columns from the fixture schema" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {RequiredColumns,
                rules: [
                  [
                    only: [
                      [schema: TestDatabase.schema(), table: "orders"],
                      [schema: TestDatabase.schema(), table: "events"]
                    ],
                    columns: ["tenant_id", "account_id"]
                  ]
                ]}
             ])

    assert issue.meta.table == "orders"
    assert issue.meta.missing_columns == ["tenant_id"]
  end

  test "returns issue metadata for missing required columns" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {RequiredColumns,
                rules: [
                  [
                    only: [schema: TestDatabase.schema(), table: "indexed_orders"],
                    columns: ["tenant_id", "account_id"]
                  ]
                ]}
             ])

    assert issue.message ==
             "expected #{TestDatabase.schema()}.indexed_orders to include required columns account_id, tenant_id"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "indexed_orders"
    assert issue.meta.missing_columns == ["account_id", "tenant_id"]
  end

  test "passes when scoped to tables with all required columns" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {RequiredColumns,
                rules: [
                  [
                    only: [
                      [schema: TestDatabase.schema(), table: "accounts"],
                      [schema: TestDatabase.schema(), table: "events"]
                    ],
                    columns: ["tenant_id", "account_id"]
                  ]
                ]}
             ])
  end

  test "skips tables with global exceptions" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {RequiredColumns,
                rules: [
                  [
                    only: [schema: TestDatabase.schema(), table: "orders"],
                    columns: ["tenant_id"],
                    except: [[schema: TestDatabase.schema(), table: "orders"]]
                  ]
                ]}
             ])
  end

  test "skips tables with rule-level exceptions" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {RequiredColumns,
                rules: [
                  [
                    only: [
                      [schema: TestDatabase.schema(), table: "orders"],
                      [schema: TestDatabase.pg_schema(), table: "orders"]
                    ],
                    columns: ["tenant_id"],
                    except: [[schema: TestDatabase.schema(), table: "orders"]]
                  ]
                ]}
             ])

    assert issue.meta.schema == TestDatabase.pg_schema()
    assert issue.meta.table == "orders"
  end

  test "reports user schemas that start with pg but not pg underscore" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {RequiredColumns,
                rules: [
                  [
                    only: [schema: TestDatabase.pg_schema(), table: "orders"],
                    columns: ["tenant_id"]
                  ]
                ]}
             ])

    assert issue.meta.schema == TestDatabase.pg_schema()
  end

  defp target do
    TestDatabase.start_repo!()
    TestDatabase.reset_fixtures!()

    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    Postgres.target(repo: TestRepo)
  end
end
