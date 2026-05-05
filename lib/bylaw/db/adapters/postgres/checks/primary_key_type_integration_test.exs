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

  test "reports primary key columns with unexpected types" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    where: [schema: TestDatabase.schema(), tables: ["users", "uuid_users"]],
                    type: "uuid"
                  ]
                ]}
             ])

    assert issue.message ==
             "expected #{TestDatabase.schema()}.users primary key column id to use type uuid, got bigint"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "users"
    assert issue.meta.column == "id"
    assert issue.meta.actual_type == "bigint"
    assert issue.meta.expected_types == ["uuid"]
  end

  test "passes when scoped primary keys use an accepted type" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    where: [schema: TestDatabase.schema(), tables: ["users", "uuid_users"]],
                    types: ["bigint", "uuid"]
                  ]
                ]}
             ])
  end

  test "skips tables with global exceptions" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {PrimaryKeyType,
                rules: [
                  [
                    where: [schema: TestDatabase.schema(), table: "users"],
                    type: "uuid"
                  ]
                ],
                except: [[schema: TestDatabase.schema(), table: "users"]]}
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
