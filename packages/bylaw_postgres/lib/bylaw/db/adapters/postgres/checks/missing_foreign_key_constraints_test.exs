defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraintsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every foreign-key-shaped column has a constraint" do
      target = target({:ok, result([])})

      assert :ok = MissingForeignKeyConstraints.validate(target, [])

      assert_received {:query, sql, [nil, nil], []}
      assert sql =~ "attribute.attname LIKE"
      assert sql =~ "constraint_record.contype = 'f'"
      assert sql =~ "constraint_record.contype = 'p'"
    end

    test "returns an issue when a foreign-key-shaped column has no constraint" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "account_id"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = MissingForeignKeyConstraints.validate(target, [])

      assert issue.check == MissingForeignKeyConstraints
      assert issue.target == target

      assert issue.message ==
               "expected public.orders.account_id to declare a foreign key constraint"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "orders",
               column: "account_id"
             }
    end

    test "accepts single-rule shorthand for scoped validation" do
      target = target({:ok, result([])})

      assert :ok =
               MissingForeignKeyConstraints.validate(target,
                 rules: [
                   where: [
                     schemas: ["public", "billing"],
                     tables: ["orders", "line_items"]
                   ]
                 ]
               )

      assert_received {:query, _sql, [nil, nil], []}
    end

    test "returns every missing foreign key constraint issue" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "account_id"],
             ["public", "line_items", "shipment_id"]
           ])}
        )

      assert {:error, issues} = MissingForeignKeyConstraints.validate(target, [])

      assert Enum.map(issues, & &1.meta.column) == ["account_id", "shipment_id"]
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               schema_name: "public",
               table_name: "orders",
               column_name: "account_id"
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = MissingForeignKeyConstraints.validate(target, [])

      assert issue.meta.table == "orders"
      assert issue.meta.column == "account_id"
    end

    test "skips validation when disabled" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = MissingForeignKeyConstraints.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_constraints option: :unknown/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, unknown: true)
                   end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected missing_foreign_key_constraints opts to be a keyword list/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, [:not_keyword])
                   end
    end

    test "requires options to be a list" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected missing_foreign_key_constraints opts to be a keyword list/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, :not_a_list)
                   end
    end

    test "rejects top-level schema filters" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_constraints option: :schemas/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, schemas: [])
                   end

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_constraints option: :schemas/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, schemas: [:public])
                   end
    end

    test "rejects top-level table filters" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_constraints option: :tables/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, tables: [])
                   end

      assert_raise ArgumentError,
                   ~r/unknown missing_foreign_key_constraints option: :tables/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, tables: [""])
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} = MissingForeignKeyConstraints.validate(target, [])

      assert issue.message == "could not inspect Postgres foreign key candidate columns"

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
        MissingForeignKeyConstraints.validate(target, [])
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
      columns: ["schema_name", "table_name", "column_name"],
      rows: rows
    }
  end
end
