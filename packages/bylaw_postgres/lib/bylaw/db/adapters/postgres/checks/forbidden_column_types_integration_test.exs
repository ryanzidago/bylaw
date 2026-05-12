defmodule Bylaw.Db.Adapters.Postgres.Checks.ForbiddenColumnTypesIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ForbiddenColumnTypes
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "reports json columns from the fixture schema" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               {ForbiddenColumnTypes,
                rules: [
                  [
                    where: [schemas: [TestDatabase.schema()], tables: ["column_type_examples"]],
                    types: ["json"]
                  ]
                ]}
             ])

    assert Enum.map(issues, & &1.meta.column) == ["json_payload", "raw_payload"]
    assert Enum.all?(issues, &match?(%Issue{}, &1))
    assert Enum.all?(issues, &(&1.meta.type == "json"))
  end

  test "does not report jsonb when only json is forbidden" do
    target = target()

    assert :ok =
             Postgres.validate([target], [
               {ForbiddenColumnTypes,
                rules: [
                  [
                    where: [schemas: [TestDatabase.schema()], tables: ["column_type_examples"]],
                    types: ["json"],
                    except: [[columns: ["json_payload", "raw_payload"]]]
                  ]
                ]}
             ])
  end

  test "reports formatted character types with regex rules" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForbiddenColumnTypes,
                rules: [
                  [
                    where: [schemas: [TestDatabase.schema()], tables: ["column_type_examples"]],
                    types: [[type: ~r/^character\(/, prefer: "text"]]
                  ]
                ]}
             ])

    assert issue.message ==
             "expected #{TestDatabase.schema()}.column_type_examples.fixed_code not to use forbidden type character(8); prefer text"

    assert issue.meta.column == "fixed_code"
    assert issue.meta.type == "character(8)"
    assert issue.meta.prefer == "text"
  end

  test "skips configured exception columns" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {ForbiddenColumnTypes,
                rules: [
                  [
                    where: [schemas: [TestDatabase.schema()], tables: ["column_type_examples"]],
                    types: ["json"],
                    except: [
                      [
                        schemas: [TestDatabase.schema()],
                        tables: ["column_type_examples"],
                        columns: ["raw_payload"]
                      ]
                    ]
                  ]
                ]}
             ])

    assert issue.meta.column == "json_payload"
  end

  defp target do
    TestDatabase.start_repo!()
    TestDatabase.reset_fixtures!()

    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    Postgres.target(repo: TestRepo)
  end
end
