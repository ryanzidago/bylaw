defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullabilityTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every foreign key column is not nullable" do
      target = target({:ok, result([])})

      assert :ok = ForeignKeyNullability.validate(target, [])

      assert_received {:query, sql, [nil, nil], []}
      assert sql =~ "pg_catalog.pg_constraint"
      assert sql =~ "NOT attribute.attnotnull"
    end

    test "returns an issue when one foreign key column is nullable" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "orders_user_id_fkey", "user_id"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = ForeignKeyNullability.validate(target, [])

      assert issue.check == ForeignKeyNullability
      assert issue.target == target

      assert issue.message ==
               "expected foreign key orders_user_id_fkey on public.orders.user_id to be NOT NULL"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "orders",
               constraint: "orders_user_id_fkey",
               column: "user_id"
             }
    end

    test "accepts single-rule shorthand for scoped validation" do
      target = target({:ok, result([])})

      assert :ok =
               ForeignKeyNullability.validate(target,
                 rules: [
                   where: [
                     schemas: ["public", "billing"],
                     tables: ["orders", "line_items"]
                   ]
                 ]
               )

      assert_received {:query, _sql, [nil, nil], []}
    end

    test "returns every nullable foreign key column issue" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "orders_user_id_fkey", "user_id"],
             ["public", "line_items", "line_items_order_id_fkey", "order_id"]
           ])}
        )

      assert {:error, issues} = ForeignKeyNullability.validate(target, [])

      assert Enum.map(issues, & &1.meta.column) == [
               "user_id",
               "order_id"
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
               column_name: "user_id"
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = ForeignKeyNullability.validate(target, [])

      assert issue.meta.constraint == "orders_user_id_fkey"
      assert issue.meta.column == "user_id"
    end

    test "skips matching exceptions" do
      target =
        target(
          {:ok,
           result([
             ["public", "runs", "runs_assistant_message_id_fkey", "assistant_message_id"],
             ["public", "messages", "messages_parent_message_id_fkey", "parent_message_id"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               ForeignKeyNullability.validate(target,
                 rules: [
                   except: [
                     [tables: ["runs"], columns: ["assistant_message_id"]],
                     [constraints: [~r/^runs_/]]
                   ]
                 ]
               )

      assert issue.meta.table == "messages"
      assert issue.meta.column == "parent_message_id"
    end

    test "skips validation when disabled" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = ForeignKeyNullability.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown foreign_key_nullability option: :unknown/, fn ->
        ForeignKeyNullability.validate(target, unknown: true)
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_nullability opts to be a keyword list/,
                   fn ->
                     ForeignKeyNullability.validate(target, [:not_keyword])
                   end
    end

    test "requires options to be a list" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_nullability opts to be a keyword list/,
                   fn ->
                     ForeignKeyNullability.validate(target, :not_a_list)
                   end
    end

    test "rejects top-level schema filters" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown foreign_key_nullability option: :schemas/,
                   fn ->
                     ForeignKeyNullability.validate(target, schemas: [])
                   end

      assert_raise ArgumentError,
                   ~r/unknown foreign_key_nullability option: :schemas/,
                   fn ->
                     ForeignKeyNullability.validate(target, schemas: [:public])
                   end
    end

    test "rejects top-level table filters" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown foreign_key_nullability option: :tables/,
                   fn ->
                     ForeignKeyNullability.validate(target, tables: [])
                   end

      assert_raise ArgumentError,
                   ~r/unknown foreign_key_nullability option: :tables/,
                   fn ->
                     ForeignKeyNullability.validate(target, tables: [""])
                   end
    end

    test "rejects top-level exceptions and validates rule exceptions" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown foreign_key_nullability option: :except/,
                   fn ->
                     ForeignKeyNullability.validate(target, except: ["orders"])
                   end

      assert_raise ArgumentError,
                   ~r/expected foreign_key_nullability :except to be a matcher or non-empty list of matchers/,
                   fn ->
                     ForeignKeyNullability.validate(target,
                       rules: [except: ["orders"]]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/unknown foreign_key_nullability :except matcher option: :unknown/,
                   fn ->
                     ForeignKeyNullability.validate(target,
                       rules: [except: [unknown: "orders"]]
                     )
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} = ForeignKeyNullability.validate(target, [])

      assert issue.message == "could not inspect Postgres foreign key nullability"

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
        ForeignKeyNullability.validate(target, [])
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
      columns: ["schema_name", "table_name", "constraint_name", "column_name"],
      rows: rows
    }
  end
end
