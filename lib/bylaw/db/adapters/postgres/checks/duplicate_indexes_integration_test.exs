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

  test "reports duplicate indexes from the fixture schema" do
    target = target()

    assert {:error, [%Issue{} = issue]} =
             Postgres.validate([target], [
               DuplicateIndexes
             ])

    assert issue.message =~ "expected duplicate indexes"
    assert issue.meta.size == "16 kB"

    assert issue.meta.indexes == [
             "#{TestDatabase.schema()}.duplicate_index_orders_user_id_idx",
             "#{TestDatabase.schema()}.duplicate_index_orders_user_id_duplicate_idx"
           ]

    assert issue.meta.source == :ecto_psql_extras
  end

  defp target do
    TestDatabase.start_repo!()
    TestDatabase.reset_fixtures!()

    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    Postgres.target(repo: TestRepo)
  end
end
