defmodule Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeysIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeys
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports scoped foreign keys that omit scope columns" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ScopedForeignKeys,
                rules: [
                  [where: [schemas: [TestDatabase.scoped_schema()]], scope_columns: ["tenant_id"]]
                ]}
             ])

    assert issue.meta.table == "scoped_orders_missing_scope"
    assert issue.meta.constraint == "scoped_orders_missing_scope_customer_id_fkey"
  end

  test "returns issue metadata for scoped foreign keys" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ScopedForeignKeys,
                rules: [
                  [
                    where: [
                      schemas: [TestDatabase.scoped_schema()],
                      tables: ["scoped_orders_missing_scope"]
                    ],
                    scope_columns: ["tenant_id"]
                  ]
                ]}
             ])

    assert issue.message ==
             "expected foreign key scoped_orders_missing_scope_customer_id_fkey on #{TestDatabase.scoped_schema()}.scoped_orders_missing_scope to include required scope columns tenant_id"

    assert issue.meta.schema == TestDatabase.scoped_schema()
    assert issue.meta.table == "scoped_orders_missing_scope"
    assert issue.meta.constraint == "scoped_orders_missing_scope_customer_id_fkey"
    assert issue.meta.columns == ["customer_id"]
    assert issue.meta.referenced_schema == TestDatabase.scoped_schema()
    assert issue.meta.referenced_table == "scoped_customers"
    assert issue.meta.referenced_columns == ["id"]
    assert issue.meta.scope_columns == ["tenant_id"]
  end

  test "passes when scoped foreign keys include scope columns" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ScopedForeignKeys,
                rules: [
                  [
                    where: [
                      schemas: [TestDatabase.scoped_schema()],
                      tables: ["scoped_orders_with_scope"]
                    ],
                    scope_columns: ["tenant_id"]
                  ]
                ]}
             ])
  end

  test "passes when the referenced table is unscoped" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ScopedForeignKeys,
                rules: [
                  [
                    where: [
                      schemas: [TestDatabase.scoped_schema()],
                      tables: ["scoped_orders_with_global_status"]
                    ],
                    scope_columns: ["tenant_id"]
                  ]
                ]}
             ])
  end

  test "passes when the child table is unscoped" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ScopedForeignKeys,
                rules: [
                  [
                    where: [schemas: [TestDatabase.scoped_schema()], tables: ["global_imports"]],
                    scope_columns: ["tenant_id"]
                  ]
                ]}
             ])
  end

  test "skips intentional global references with exceptions" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ScopedForeignKeys,
                rules: [
                  [
                    where: [schemas: [TestDatabase.scoped_schema()]],
                    scope_columns: ["tenant_id"],
                    except: [[referenced_tables: ["scoped_customers"]]]
                  ]
                ]}
             ])
  end

  defp target do
    TestDatabase.start_repo!()
    TestDatabase.reset_fixtures!()

    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    Postgres.target(repo: TestRepo)
  end
end
