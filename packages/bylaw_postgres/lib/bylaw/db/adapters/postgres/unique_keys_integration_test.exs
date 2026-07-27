defmodule Bylaw.Db.Adapters.Postgres.UniqueKeysIntegrationTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres.UniqueKeys
  alias Bylaw.Db.Postgres.TestDatabase
  alias Bylaw.Db.Postgres.TestRepo
  alias Ecto.Adapters.SQL.Sandbox

  @moduletag :postgres
  @moduletag timeout: 30_000

  test "returns only conservative unique keys from the live Postgres catalogue" do
    start_target()

    catalogue = UniqueKeys.fetch!(TestRepo)
    source = {TestDatabase.schema(), "unique_key_examples"}

    assert catalogue[source] == [
             ["id"],
             ["included_code"],
             ["nulls_not_distinct_code"],
             ["organisation_key", "sequence"],
             ["slug"]
           ]

    refute ["nullable_code"] in catalogue[source]
    refute ["expression_value"] in catalogue[source]
    refute ["deferred_code"] in catalogue[source]
    refute ["custom_operator_code"] in catalogue[source]
  end

  test "adds an unqualified alias for a table visible through the search path" do
    start_target()

    TestDatabase.query!("SET search_path TO #{quote_identifier(TestDatabase.schema())}, public")

    catalogue = UniqueKeys.fetch!(TestRepo)

    assert catalogue[{nil, "unique_key_examples"}] ==
             catalogue[{TestDatabase.schema(), "unique_key_examples"}]
  end

  defp start_target do
    TestDatabase.start_repo!()
    TestDatabase.reset_fixtures!()

    owner = Sandbox.start_owner!(TestRepo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
  end

  defp quote_identifier(identifier) do
    escaped = String.replace(identifier, ~s("), ~s(""))
    ~s("#{escaped}")
  end
end
