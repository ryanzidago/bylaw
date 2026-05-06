defmodule Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyTypeTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when all primary key columns use configured types" do
      target = target({:ok, result([])})

      assert :ok = PrimaryKeyType.validate(target, types: ["uuid"])

      assert_received {:query, sql, [nil, nil, ["uuid"]], []}
      assert sql =~ "pg_catalog.pg_constraint"
      assert sql =~ "format_type"
      assert sql =~ "missing_primary_key"
      assert sql =~ "wrong_type"
    end

    test "returns an issue when a table has no primary key" do
      target =
        target(
          {:ok,
           result([
             ["public", "audit_log", nil, nil, "missing_primary_key"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = PrimaryKeyType.validate(target, types: ["uuid"])

      assert issue.check == PrimaryKeyType
      assert issue.target == target
      assert issue.message == "expected public.audit_log to declare a primary key"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "audit_log",
               types: ["uuid"],
               actual_type: nil,
               reason: :missing_primary_key
             }
    end

    test "returns an issue when a primary key column has the wrong type" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "id", "bigint", "wrong_type"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = PrimaryKeyType.validate(target, types: ["uuid"])

      assert issue.message ==
               "expected primary key public.orders.id to use one of: uuid, got: bigint"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "orders",
               column: "id",
               types: ["uuid"],
               actual_type: "bigint",
               reason: :wrong_type
             }
    end

    test "supports composite primary keys" do
      target =
        target(
          {:ok,
           result([
             ["public", "memberships", "tenant_id", "bigint", "wrong_type"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               PrimaryKeyType.validate(target, types: ["uuid"])

      assert issue.meta.table == "memberships"
      assert issue.meta.column == "tenant_id"
      assert issue.meta.actual_type == "bigint"
    end

    test "passes schema and table filters as check scope" do
      target = target({:ok, result([])})

      assert :ok =
               PrimaryKeyType.validate(target,
                 schemas: ["public", "billing"],
                 tables: ["orders", "line_items"],
                 types: ["uuid", "bigint"]
               )

      assert_received {:query, _sql,
                       [["public", "billing"], ["orders", "line_items"], ["uuid", "bigint"]], []}
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               schema_name: "public",
               table_name: "orders",
               column_name: "id",
               actual_type: "bigint",
               reason: :wrong_type
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = PrimaryKeyType.validate(target, types: ["uuid"])

      assert issue.meta.table == "orders"
      assert issue.meta.column == "id"
      assert issue.meta.actual_type == "bigint"
    end

    test "skips matching exceptions" do
      target =
        target(
          {:ok,
           result([
             ["public", "schema_migrations", "version", "bigint", "wrong_type"],
             ["public", "orders", "id", "bigint", "wrong_type"],
             ["public", "audit_log", nil, nil, "missing_primary_key"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               PrimaryKeyType.validate(target,
                 types: ["uuid"],
                 except: [
                   [table: "schema_migrations"],
                   [schema: "public", tables: ["audit_log"]]
                 ]
               )

      assert issue.meta.table == "orders"
      assert issue.meta.column == "id"
    end

    test "supports column exceptions on composite primary key columns" do
      target =
        target(
          {:ok,
           result([
             ["public", "memberships", "tenant_id", "bigint", "wrong_type"],
             ["public", "memberships", "user_id", "bigint", "wrong_type"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               PrimaryKeyType.validate(target,
                 types: ["uuid"],
                 except: [[table: "memberships", column: "tenant_id"]]
               )

      assert issue.meta.column == "user_id"
    end

    test "skips validation when disabled without requiring types" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = PrimaryKeyType.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown primary_key_type option: :unknown/, fn ->
        PrimaryKeyType.validate(target, types: ["uuid"], unknown: true)
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type opts to be a keyword list/,
                   fn ->
                     PrimaryKeyType.validate(target, [:not_keyword])
                   end
    end

    test "requires options to be a list" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type opts to be a keyword list/,
                   fn ->
                     PrimaryKeyType.validate(target, :not_a_list)
                   end
    end

    test "requires types when validation is enabled" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/expected primary_key_type to include :types/, fn ->
        PrimaryKeyType.validate(target, [])
      end
    end

    test "requires types to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :types to be a non-empty list of strings/,
                   fn ->
                     PrimaryKeyType.validate(target, types: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :types to be a non-empty list of strings/,
                   fn ->
                     PrimaryKeyType.validate(target, types: [:uuid])
                   end
    end

    test "requires schema filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :schemas to be a non-empty list of strings/,
                   fn ->
                     PrimaryKeyType.validate(target, schemas: [], types: ["uuid"])
                   end

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :schemas to be a non-empty list of strings/,
                   fn ->
                     PrimaryKeyType.validate(target, schemas: [:public], types: ["uuid"])
                   end
    end

    test "requires table filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :tables to be a non-empty list of strings/,
                   fn ->
                     PrimaryKeyType.validate(target, tables: [], types: ["uuid"])
                   end

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :tables to be a non-empty list of strings/,
                   fn ->
                     PrimaryKeyType.validate(target, tables: [""], types: ["uuid"])
                   end
    end

    test "requires exceptions to be matchers" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :except to be a matcher or non-empty list of matchers/,
                   fn ->
                     PrimaryKeyType.validate(target, types: ["uuid"], except: ["orders"])
                   end

      assert_raise ArgumentError,
                   ~r/unknown primary_key_type :except matcher option: :unknown/,
                   fn ->
                     PrimaryKeyType.validate(target, types: ["uuid"], except: [unknown: "orders"])
                   end

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :except :columns to be a matcher value or non-empty list of matcher values/,
                   fn ->
                     PrimaryKeyType.validate(target, types: ["uuid"], except: [columns: []])
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} =
               PrimaryKeyType.validate(target,
                 rules: [
                   [
                     only: [schema: "public", table: "orders"],
                     types: ["uuid"],
                     except: [[table: "schema_migrations"]]
                   ]
                 ]
               )

      assert issue.message == "could not inspect Postgres primary key types"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               rules: [
                 %{
                   only: [[schema: "public", table: "orders"]],
                   types: ["uuid"],
                   except: [[table: "schema_migrations"]]
                 }
               ],
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        PrimaryKeyType.validate(target, types: ["uuid"])
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
      columns: ["schema_name", "table_name", "column_name", "actual_type", "reason"],
      rows: rows
    }
  end
end
