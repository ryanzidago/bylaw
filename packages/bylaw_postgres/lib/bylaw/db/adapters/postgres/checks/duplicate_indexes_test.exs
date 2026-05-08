defmodule Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexesTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when no equivalent indexes are found" do
      target = target({:ok, result([])})

      assert :ok = DuplicateIndexes.validate(target, [])

      assert_received {:query, sql, [nil, nil], []}
      assert sql =~ "pg_catalog.pg_index"
      assert sql =~ "index_count > 1"
    end

    test "returns an issue when a table has duplicate indexes" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", ["orders_status_idx", "orders_status_duplicate_idx"]]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = DuplicateIndexes.validate(target, [])

      assert issue.check == DuplicateIndexes
      assert issue.target == target

      assert issue.message ==
               "expected public.orders to have no duplicate indexes, found orders_status_idx, orders_status_duplicate_idx"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "orders",
               indexes: ["orders_status_idx", "orders_status_duplicate_idx"]
             }
    end

    test "passes schema and table filters as check scope" do
      target = target({:ok, result([])})

      assert :ok =
               DuplicateIndexes.validate(target,
                 schemas: ["public", "billing"],
                 tables: ["orders", "line_items"]
               )

      assert_received {:query, _sql, [["public", "billing"], ["orders", "line_items"]], []}
    end

    test "returns every duplicate index group issue" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", ["orders_status_idx", "orders_status_duplicate_idx"]],
             ["public", "line_items", ["line_items_sku_idx", "line_items_sku_duplicate_idx"]]
           ])}
        )

      assert {:error, issues} = DuplicateIndexes.validate(target, [])

      assert Enum.map(issues, & &1.meta.table) == ["orders", "line_items"]
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               schema_name: "public",
               table_name: "orders",
               index_names: ["orders_status_idx", "orders_status_duplicate_idx"]
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = DuplicateIndexes.validate(target, [])

      assert issue.meta.table == "orders"
      assert issue.meta.indexes == ["orders_status_idx", "orders_status_duplicate_idx"]
    end

    test "skips validation when disabled" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = DuplicateIndexes.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown duplicate_indexes option: :unknown/, fn ->
        DuplicateIndexes.validate(target, unknown: true)
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected duplicate_indexes opts to be a keyword list/,
                   fn ->
                     DuplicateIndexes.validate(target, [:not_keyword])
                   end
    end

    test "requires options to be a list" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected duplicate_indexes opts to be a keyword list/,
                   fn ->
                     DuplicateIndexes.validate(target, :not_a_list)
                   end
    end

    test "requires schema filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected duplicate_indexes :schemas to be a non-empty list of strings/,
                   fn ->
                     DuplicateIndexes.validate(target, schemas: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected duplicate_indexes :schemas to be a non-empty list of strings/,
                   fn ->
                     DuplicateIndexes.validate(target, schemas: [:public])
                   end
    end

    test "requires table filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected duplicate_indexes :tables to be a non-empty list of strings/,
                   fn ->
                     DuplicateIndexes.validate(target, tables: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected duplicate_indexes :tables to be a non-empty list of strings/,
                   fn ->
                     DuplicateIndexes.validate(target, tables: [""])
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} = DuplicateIndexes.validate(target, [])

      assert issue.message == "could not inspect Postgres indexes"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               rules: [%{only: [], except: []}],
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        DuplicateIndexes.validate(target, [])
      end
    end
  end

  defp target(query_result) do
    parent = self()

    Postgres.target(
      query: fn _target, sql, params, opts ->
        send(parent, {:query, sql, params, opts})
        query_result
      end
    )
  end

  defp result(rows) do
    %{
      columns: ["schema_name", "table_name", "index_names"],
      rows: rows
    }
  end
end
