defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexesTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every foreign key has a supporting index" do
      target = target({:ok, result([])})

      assert :ok = MissingForeignKeyIndexes.validate(target, [])

      assert_received {:query, sql, [nil, nil], []}
      assert sql =~ "pg_catalog.pg_constraint"
      assert sql =~ "pg_catalog.pg_index"
    end

    test "returns an issue when one foreign key is missing a supporting index" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "orders_user_id_fkey", ["user_id"]]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = MissingForeignKeyIndexes.validate(target, [])

      assert issue.check == MissingForeignKeyIndexes
      assert issue.target == target

      assert issue.message ==
               "expected foreign key orders_user_id_fkey on public.orders to have a supporting index"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "orders",
               constraint: "orders_user_id_fkey",
               columns: ["user_id"]
             }
    end

    test "accepts single-rule shorthand for scoped validation" do
      target = target({:ok, result([])})

      assert :ok =
               MissingForeignKeyIndexes.validate(target,
                 rules: [
                   where: [
                     schemas: ["public", "billing"],
                     tables: ["orders", "line_items"]
                   ]
                 ]
               )

      assert_received {:query, _sql, [nil, nil], []}
    end

    test "returns every missing foreign key index issue" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "orders_user_id_fkey", ["user_id"]],
             ["public", "line_items", "line_items_order_id_fkey", ["order_id"]]
           ])}
        )

      assert {:error, issues} = MissingForeignKeyIndexes.validate(target, [])

      assert Enum.map(issues, & &1.meta.constraint) == [
               "orders_user_id_fkey",
               "line_items_order_id_fkey"
             ]
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               schema_name: "public",
               table_name: "orders",
               constraint_name: "orders_user_id_fkey",
               column_names: ["user_id"]
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = MissingForeignKeyIndexes.validate(target, [])

      assert issue.meta.constraint == "orders_user_id_fkey"
      assert issue.meta.columns == ["user_id"]
    end

    test "skips validation when disabled" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = MissingForeignKeyIndexes.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown missing_foreign_key_indexes option: :unknown/, fn ->
        MissingForeignKeyIndexes.validate(target, unknown: true)
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected missing_foreign_key_indexes opts to be a keyword list/,
                   fn ->
                     MissingForeignKeyIndexes.validate(target, [:not_keyword])
                   end
    end

    test "requires options to be a list" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected missing_foreign_key_indexes opts to be a keyword list/,
                   fn ->
                     MissingForeignKeyIndexes.validate(target, :not_a_list)
                   end
    end

    test "rejects top-level schema filters" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_indexes option: :schemas/,
                   fn ->
                     MissingForeignKeyIndexes.validate(target, schemas: [])
                   end

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_indexes option: :schemas/,
                   fn ->
                     MissingForeignKeyIndexes.validate(target, schemas: [:public])
                   end
    end

    test "rejects top-level table filters" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_indexes option: :tables/,
                   fn ->
                     MissingForeignKeyIndexes.validate(target, tables: [])
                   end

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_indexes option: :tables/,
                   fn ->
                     MissingForeignKeyIndexes.validate(target, tables: [""])
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} = MissingForeignKeyIndexes.validate(target, [])

      assert issue.message == "could not inspect Postgres foreign keys"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               rules: [%{where: [], except: []}],
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        MissingForeignKeyIndexes.validate(target, [])
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
      columns: ["schema_name", "table_name", "constraint_name", "column_names"],
      rows: rows
    }
  end
end
