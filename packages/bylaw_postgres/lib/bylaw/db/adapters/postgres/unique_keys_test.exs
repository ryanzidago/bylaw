defmodule Bylaw.Db.Adapters.Postgres.UniqueKeysTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.UniqueKeys
  alias Bylaw.Db.Target

  describe "fetch_target!/1" do
    test "returns unique column sets by schema and table" do
      target =
        target(
          {:ok,
           result([
             ["public", "posts", ["slug"], false],
             ["public", "posts", ["organisation_id", "sequence"], false],
             ["public", "posts", ["slug"], false],
             ["tenant_a", "users", ["email"], false]
           ])}
        )

      assert UniqueKeys.fetch_target!(target) == %{
               {"public", "posts"} => [
                 ["organisation_id", "sequence"],
                 ["slug"]
               ],
               {"tenant_a", "users"} => [["email"]]
             }

      assert_received {:query, sql, [], []}
      assert sql =~ "pg_catalog.pg_index"
      assert sql =~ "index_record.indisunique"
      assert sql =~ "index_record.indisvalid"
      assert sql =~ "index_record.indisready"
      assert sql =~ "index_record.indislive"
      assert sql =~ "index_record.indimmediate"
      assert sql =~ "index_record.indpred IS NULL"
      assert sql =~ "index_record.indexprs IS NULL"
      assert sql =~ "indnullsnotdistinct"
      assert sql =~ "operator_class.opcdefault"
      assert sql =~ "pg_table_is_visible"
    end

    test "adds nil-schema aliases for tables visible through the search path" do
      target =
        target(
          {:ok,
           result([
             ["public", "posts", ["id"], true],
             ["public", "posts", ["slug"], true],
             ["tenant_a", "users", ["id"], false]
           ])}
        )

      assert UniqueKeys.fetch_target!(target) == %{
               {nil, "posts"} => [["id"], ["slug"]],
               {"public", "posts"} => [["id"], ["slug"]],
               {"tenant_a", "users"} => [["id"]]
             }
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               schema_name: "public",
               table_name: "posts",
               column_names: ["id"],
               table_visible: true
             }
           ]}
        )

      assert UniqueKeys.fetch_target!(target) == %{
               {nil, "posts"} => [["id"]],
               {"public", "posts"} => [["id"]]
             }
    end

    test "raises when catalogue inspection fails" do
      target = target({:error, :database_unavailable})

      assert_raise RuntimeError,
                   "could not inspect Postgres unique keys: :database_unavailable",
                   fn ->
                     UniqueKeys.fetch_target!(target)
                   end
    end

    test "raises for malformed catalogue rows" do
      target = target({:ok, result([["public", "posts", [], true]])})

      assert_raise ArgumentError, ~r/expected a valid Postgres unique key row/, fn ->
        UniqueKeys.fetch_target!(target)
      end
    end

    test "requires a Postgres target" do
      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        UniqueKeys.fetch_target!(%Target{adapter: OtherAdapter})
      end

      assert_raise ArgumentError, ~r/expected a database target/, fn ->
        UniqueKeys.fetch_target!(:not_a_target)
      end
    end
  end

  describe "fetch!/2" do
    test "validates the repo" do
      assert_raise ArgumentError, "expected Postgres repo to be a module, got: nil", fn ->
        UniqueKeys.fetch!(nil)
      end
    end

    test "validates options" do
      assert_raise ArgumentError,
                   "expected Postgres unique key opts to be a keyword list, got: [:bad]",
                   fn ->
                     UniqueKeys.fetch!(SomeRepo, [:bad])
                   end

      assert_raise ArgumentError, "unknown Postgres unique key option: :timeout", fn ->
        UniqueKeys.fetch!(SomeRepo, timeout: 1_000)
      end
    end
  end

  defp target(response) do
    test_pid = self()

    Postgres.target(
      query: fn _target, sql, params, opts ->
        send(test_pid, {:query, sql, params, opts})
        response
      end
    )
  end

  defp result(rows) do
    %{
      columns: ["schema_name", "table_name", "column_names", "table_visible"],
      rows: rows
    }
  end

  defmodule OtherAdapter do
  end
end
