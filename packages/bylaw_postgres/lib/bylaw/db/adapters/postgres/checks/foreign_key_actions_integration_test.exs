defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActionsIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActions
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports foreign keys with unexpected delete actions from the fixture schema" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyActions,
                rules: [
                  [
                    where: [schemas: [TestDatabase.schema()], tables: ["action_messages"]],
                    on_delete: :cascade
                  ]
                ]}
             ])

    assert issue.meta.constraint == "action_messages_status_user_id_fkey"
  end

  test "returns issue metadata for foreign key action mismatches" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForeignKeyActions,
                rules: [
                  [
                    where: [
                      schemas: [TestDatabase.schema()],
                      constraints: ["action_messages_owner_user_id_fkey"]
                    ],
                    on_delete: :restrict
                  ]
                ]}
             ])

    assert issue.message ==
             "expected foreign key action_messages_owner_user_id_fkey on #{TestDatabase.schema()}.action_messages to use ON DELETE RESTRICT, got: CASCADE"

    assert issue.meta.schema == TestDatabase.schema()
    assert issue.meta.table == "action_messages"
    assert issue.meta.constraint == "action_messages_owner_user_id_fkey"
    assert issue.meta.columns == ["owner_user_id"]
    assert issue.meta.referenced_schema == TestDatabase.schema()
    assert issue.meta.referenced_table == "users"
    assert issue.meta.referenced_columns == ["id"]
  end

  test "passes when scoped rules match the configured actions" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ForeignKeyActions,
                rules: [
                  [
                    where: [
                      schemas: [TestDatabase.schema()],
                      tables: ["action_messages"],
                      columns: ["owner_user_id"],
                      referenced_tables: ["users"]
                    ],
                    on_delete: :cascade,
                    on_update: :restrict
                  ],
                  [
                    where: [
                      schemas: [TestDatabase.schema()],
                      constraints: ["action_messages_status_user_id_fkey"]
                    ],
                    on_delete: :restrict
                  ]
                ]}
             ])
  end

  test "skips matching exceptions" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ForeignKeyActions,
                rules: [
                  [
                    where: [schemas: [TestDatabase.schema()], tables: ["action_messages"]],
                    on_delete: :cascade,
                    except: [[constraints: ["action_messages_status_user_id_fkey"]]]
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
