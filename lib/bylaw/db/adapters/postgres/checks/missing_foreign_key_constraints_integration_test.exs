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

  test "reports conventional foreign key-like columns without constraints" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               {MissingForeignKeyConstraints, tables: ["loose_orders"]}
             ])

    assert issue.message ==
             "expected foreign key-like column user_id on loose_orders to have a foreign key constraint"

    assert issue.meta.table == "loose_orders"
    assert issue.meta.column == "user_id"
    assert issue.meta.source == :ecto_psql_extras
  end

  test "deduplicates repeated table findings across schemas" do
    target = target()

    assert {:error, issues} =
             Postgres.validate([target], [
               {MissingForeignKeyConstraints, tables: ["orders"]}
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
