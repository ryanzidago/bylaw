defmodule Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyTypeIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "passes for uuid primary keys in scope" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    only: [
                      schema: TestDatabase.schema(),
                      table: ["uuid_primary_key", "composite_uuid_primary_key"]
                    ],
                    types: ["uuid"]
                  ]
                ]}
             ])
  end

  test "passes for bigint primary keys in scope" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    only: [schema: TestDatabase.schema(), table: "bigint_primary_key"],
                    types: ["bigint"]
                  ]
                ]}
             ])
  end

  test "reports tables missing primary keys" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    only: [schema: TestDatabase.schema(), table: "missing_primary_key"],
                    types: ["uuid"]
                  ]
                ]}
             ])

    assert issue.message ==
             "expected #{TestDatabase.schema()}.missing_primary_key to declare a primary key"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "missing_primary_key"
    assert issue.meta.types == ["uuid"]
    assert issue.meta.actual_type == nil
    assert issue.meta.reason == :missing_primary_key
  end

  test "reports primary key columns with wrong types" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    only: [schema: TestDatabase.schema(), table: "bigint_primary_key"],
                    types: ["uuid"]
                  ]
                ]}
             ])

    assert issue.message ==
             "expected primary key #{TestDatabase.schema()}.bigint_primary_key.id to use one of: uuid, got: bigint"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "bigint_primary_key"
    assert issue.meta.column == "id"
    assert issue.meta.types == ["uuid"]
    assert issue.meta.actual_type == "bigint"
    assert issue.meta.reason == :wrong_type
  end

  test "reports mismatched columns in composite primary keys" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    only: [schema: TestDatabase.schema(), table: "composite_mixed_primary_key"],
                    types: ["uuid"]
                  ]
                ]}
             ])

    assert issue.meta.table == "composite_mixed_primary_key"
    assert issue.meta.column == "account_id"
    assert issue.meta.actual_type == "bigint"
  end

  test "accepts any configured type" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    only: [
                      schema: TestDatabase.schema(),
                      table: [
                        "uuid_primary_key",
                        "bigint_primary_key",
                        "composite_mixed_primary_key"
                      ]
                    ],
                    types: ["uuid", "bigint"]
                  ]
                ]}
             ])
  end

  test "skips intentional exceptions" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    only: [
                      schema: TestDatabase.schema(),
                      table: ["bigint_primary_key", "missing_primary_key"]
                    ],
                    types: ["uuid"],
                    except: [
                      [table: "bigint_primary_key", column: "id"],
                      [table: "missing_primary_key"]
                    ]
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
