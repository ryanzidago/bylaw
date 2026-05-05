defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyIndexesTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyIndexes
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every foreign key has a supporting index" do
      target = target({:ok, result([])})

      assert :ok = ForeignKeyIndexes.validate(target, [])

      assert_received {:query, "ecto_psql_extras.missing_fk_indexes", [nil], []}
    end

    test "returns an issue when one foreign key is missing a supporting index" do
      target =
        target(
          {:ok,
           result([
             ["orders", "user_id"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = ForeignKeyIndexes.validate(target, [])

      assert issue.check == ForeignKeyIndexes
      assert issue.target == target

      assert issue.message ==
               "expected foreign key-like column user_id on orders to have a supporting index"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               table: "orders",
               column: "user_id",
               columns: ["user_id"],
               source: :ecto_psql_extras
             }
    end

    test "passes table filters as check scope" do
      target = target({:ok, result([])})

      assert :ok =
               ForeignKeyIndexes.validate(target,
                 tables: ["orders", "line_items"]
               )

      assert_received {:query, _sql, [["orders", "line_items"]], []}
    end

    test "returns every missing foreign key index issue" do
      target =
        target(
          {:ok,
           result([
             ["orders", "user_id"],
             ["line_items", "order_id"]
           ])}
        )

      assert {:error, issues} = ForeignKeyIndexes.validate(target, [])

      assert Enum.map(issues, &{&1.meta.table, &1.meta.column}) == [
               {"orders", "user_id"},
               {"line_items", "order_id"}
             ]
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               table: "orders",
               column_name: "user_id"
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = ForeignKeyIndexes.validate(target, [])

      assert issue.meta.table == "orders"
      assert issue.meta.column == "user_id"
      assert issue.meta.columns == ["user_id"]
    end

    test "skips validation when disabled" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = ForeignKeyIndexes.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown foreign_key_indexes option: :unknown/, fn ->
        ForeignKeyIndexes.validate(target, unknown: true)
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_indexes opts to be a keyword list/,
                   fn ->
                     ForeignKeyIndexes.validate(target, [:not_keyword])
                   end
    end

    test "requires options to be a list" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_indexes opts to be a keyword list/,
                   fn ->
                     ForeignKeyIndexes.validate(target, :not_a_list)
                   end
    end

    test "rejects schema filters because ecto_psql_extras scopes by table" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown foreign_key_indexes option: :schemas/, fn ->
        ForeignKeyIndexes.validate(target, schemas: ["public"])
      end
    end

    test "requires table filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_indexes :tables to be a non-empty list of strings/,
                   fn ->
                     ForeignKeyIndexes.validate(target, tables: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected foreign_key_indexes :tables to be a non-empty list of strings/,
                   fn ->
                     ForeignKeyIndexes.validate(target, tables: [""])
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} = ForeignKeyIndexes.validate(target, [])

      assert issue.message == "could not inspect Postgres foreign key indexes"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               tables: nil,
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        ForeignKeyIndexes.validate(target, [])
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
      columns: ["table", "column_name"],
      rows: rows
    }
  end
end
