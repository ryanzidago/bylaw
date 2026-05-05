defmodule Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyTypeTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every primary key column has the expected type" do
      target =
        target(
          {:ok,
           result([
             ["public", "users", "id", "uuid"],
             ["public", "accounts", "tenant_id", "uuid"],
             ["public", "accounts", "account_id", "uuid"]
           ])}
        )

      assert :ok = PrimaryKeyType.validate(target, type: "uuid")

      assert_received {:query, sql, [], []}
      assert sql =~ "pg_catalog.format_type"
      assert sql =~ "index_record.indisprimary"
    end

    test "returns an issue when a primary key column has an unexpected type" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "id", "bigint"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = PrimaryKeyType.validate(target, type: "uuid")

      assert issue.check == PrimaryKeyType
      assert issue.target == target

      assert issue.message ==
               "expected public.orders primary key column id to use type uuid, got bigint"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "orders",
               column: "id",
               actual_type: "bigint",
               expected_types: ["uuid"],
               rule: %{
                 types: ["uuid"],
                 where: [],
                 except: []
               }
             }
    end

    test "accepts more than one allowed type" do
      target =
        target(
          {:ok,
           result([
             ["public", "users", "id", "uuid"],
             ["legacy", "users", "id", "bigint"]
           ])}
        )

      assert :ok = PrimaryKeyType.validate(target, types: ["uuid", "bigint"])
    end

    test "supports multiple scoped rules" do
      target =
        target(
          {:ok,
           result([
             ["public", "users", "id", "bigint"],
             ["public", "accounts", "tenant_id", "uuid"],
             ["public", "accounts", "account_id", "uuid"],
             ["legacy", "users", "id", "bigint"]
           ])}
        )

      assert {:error, issues} =
               PrimaryKeyType.validate(target,
                 rules: [
                   [where: [schema: "public"], type: "uuid"],
                   [where: [schema: "legacy"], types: ["integer", "uuid"]]
                 ]
               )

      assert Enum.map(issues, &{&1.meta.schema, &1.meta.table, &1.meta.column}) == [
               {"public", "users", "id"},
               {"legacy", "users", "id"}
             ]

      assert_received {:query, _sql, [], []}
      assert_received {:query, _sql, [], []}
    end

    test "applies global and rule-level exceptions" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", "id", "bigint"],
             ["public", "schema_migrations", "version", "bigint"],
             ["legacy", "orders", "id", "bigint"]
           ])}
        )

      assert :ok =
               PrimaryKeyType.validate(target,
                 rules: [
                   [
                     where: [[schema: "public"], [schema: "legacy"]],
                     type: "uuid",
                     except: [[schema: "legacy", table: "orders"]]
                   ]
                 ],
                 except: [[table: "schema_migrations"], [table: "orders", column: "id"]]
               )
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
               column_type: "bigint"
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = PrimaryKeyType.validate(target, type: "uuid")

      assert issue.meta.table == "orders"
      assert issue.meta.actual_type == "bigint"
    end

    test "skips validation when disabled without requiring a type" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = PrimaryKeyType.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown primary_key_type option: :unknown/, fn ->
        PrimaryKeyType.validate(target, type: "uuid", unknown: true)
      end
    end

    test "rejects unknown rule options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown primary_key_type rule option: :unknown/, fn ->
        PrimaryKeyType.validate(target, rules: [[type: "uuid", unknown: true]])
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

    test "requires type, types, or rules when validation is enabled" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type to include :type, :types, or :rules/,
                   fn ->
                     PrimaryKeyType.validate(target, [])
                   end
    end

    test "rejects direct type options mixed with rules" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type to include :type, :types, or :rules, not both/,
                   fn ->
                     PrimaryKeyType.validate(target, type: "uuid", rules: [[type: "bigint"]])
                   end
    end

    test "rejects type and types together" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type to include :type or :types, not both/,
                   fn ->
                     PrimaryKeyType.validate(target, type: "uuid", types: ["bigint"])
                   end
    end

    test "requires types to be non-empty strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :type or :types to be non-empty strings/,
                   fn ->
                     PrimaryKeyType.validate(target, type: "")
                   end

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :type or :types to be non-empty strings/,
                   fn ->
                     PrimaryKeyType.validate(target, rules: [[types: [:uuid]]])
                   end
    end

    test "requires rules to be a non-empty list of keyword rules" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :rules to be a non-empty list of keyword rules/,
                   fn ->
                     PrimaryKeyType.validate(target, rules: [])
                   end
    end

    test "requires matchers to be keyword matchers or non-empty matcher lists" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :where to be a matcher or non-empty list of matchers/,
                   fn ->
                     PrimaryKeyType.validate(target, rules: [[where: [], type: "uuid"]])
                   end

      assert_raise ArgumentError,
                   ~r/expected primary_key_type :except to be a matcher or non-empty list of matchers/,
                   fn ->
                     PrimaryKeyType.validate(target,
                       type: "uuid",
                       except: [[schema: "public"], [columns: [""]]]
                     )
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} =
               PrimaryKeyType.validate(target,
                 rules: [[where: [schema: "public"], type: "uuid"]],
                 except: [[table: "schema_migrations"]]
               )

      assert issue.message == "could not inspect Postgres primary key types"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               rule: %{
                 types: ["uuid"],
                 where: [[schema: "public"]],
                 except: []
               },
               except: [[table: "schema_migrations"]],
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        PrimaryKeyType.validate(target, type: "uuid")
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
      columns: ["schema_name", "table_name", "column_name", "column_type"],
      rows: rows
    }
  end
end
