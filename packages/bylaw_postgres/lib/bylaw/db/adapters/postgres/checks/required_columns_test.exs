defmodule Bylaw.Db.Adapters.Postgres.Checks.RequiredColumnsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every table has the required columns" do
      target = target({:ok, result([])})

      assert :ok = RequiredColumns.validate(target, columns: ["tenant_id", "account_id"])

      assert_received {:query, sql, [["tenant_id", "account_id"]], []}
      assert sql =~ "pg_catalog.pg_attribute"
      assert sql =~ "missing_columns"
    end

    test "returns an issue when a table is missing required columns" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", ["tenant_id", "account_id"]]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               RequiredColumns.validate(target, columns: ["tenant_id", "account_id"])

      assert issue.check == RequiredColumns
      assert issue.target == target

      assert issue.message ==
               "expected public.orders to include required columns tenant_id, account_id"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "orders",
               missing_columns: ["tenant_id", "account_id"],
               rule: %{
                 columns: ["tenant_id", "account_id"],
                 where: [],
                 except: []
               }
             }
    end

    test "supports multiple scoped rules" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", ["tenant_id"]],
             ["billing", "invoice_items", ["tenant_id"]],
             ["audit", "events", ["actor_id"]],
             ["legacy", "events", ["actor_id"]]
           ])}
        )

      assert {:error, issues} =
               RequiredColumns.validate(target,
                 rules: [
                   [
                     where: [
                       [schemas: ["public"], tables: [~r/^orders/]],
                       [schemas: ["billing"], tables: [~r/^invoice_/]]
                     ],
                     columns: ["tenant_id"]
                   ],
                   [where: [schemas: ["audit"]], columns: ["actor_id"]]
                 ]
               )

      assert Enum.map(issues, &{&1.meta.schema, &1.meta.table, &1.meta.missing_columns}) == [
               {"public", "orders", ["tenant_id"]},
               {"billing", "invoice_items", ["tenant_id"]},
               {"audit", "events", ["actor_id"]}
             ]

      assert_received {:query, _sql, [["tenant_id"]], []}
      assert_received {:query, _sql, [["actor_id"]], []}
    end

    test "supports where as a rule scope" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", ["tenant_id"]],
             ["billing", "invoice_items", ["tenant_id"]]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               RequiredColumns.validate(target,
                 rules: [
                   [
                     where: [schemas: ["public"], tables: ["orders"]],
                     columns: ["tenant_id"]
                   ]
                 ]
               )

      assert issue.meta.schema == "public"
      assert issue.meta.table == "orders"
      assert issue.meta.rule.where == [[schema: ["public"], table: ["orders"]]]
    end

    test "applies global and rule-level exceptions" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", ["tenant_id"]],
             ["public", "schema_migrations", ["tenant_id"]],
             ["billing", "invoice_items", ["tenant_id"]]
           ])}
        )

      assert :ok =
               RequiredColumns.validate(target,
                 rules: [
                   [
                     where: [[schemas: ["public"]], [schemas: ["billing"]]],
                     columns: ["tenant_id"],
                     except: [
                       [schemas: ["billing"], tables: [~r/^invoice_/]],
                       [tables: ["schema_migrations"]],
                       [tables: ["orders"]]
                     ]
                   ]
                 ]
               )
    end

    test "returns every matching required column issue" do
      target =
        target(
          {:ok,
           result([
             ["public", "orders", ["tenant_id"]],
             ["public", "line_items", ["tenant_id", "account_id"]]
           ])}
        )

      assert {:error, issues} = RequiredColumns.validate(target, columns: ["tenant_id"])

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
               missing_columns: ["tenant_id"]
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} =
               RequiredColumns.validate(target, columns: ["tenant_id"])

      assert issue.meta.table == "orders"
      assert issue.meta.missing_columns == ["tenant_id"]
    end

    test "skips validation when disabled without requiring columns" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = RequiredColumns.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown required_columns option: :unknown/, fn ->
        RequiredColumns.validate(target, columns: ["tenant_id"], unknown: true)
      end
    end

    test "rejects unknown rule options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown required_columns rule option: :unknown/, fn ->
        RequiredColumns.validate(target, rules: [[columns: ["tenant_id"], unknown: true]])
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns opts to be a keyword list/,
                   fn ->
                     RequiredColumns.validate(target, [:not_keyword])
                   end
    end

    test "requires columns or rules when validation is enabled" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns to include :columns or :rules/,
                   fn ->
                     RequiredColumns.validate(target, [])
                   end
    end

    test "rejects columns and rules together" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns to use rule-level :columns when :rules is provided/,
                   fn ->
                     RequiredColumns.validate(target,
                       columns: ["tenant_id"],
                       rules: [[columns: ["account_id"]]]
                     )
                   end
    end

    test "rejects top-level exceptions when rules are provided" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns to use rule-level :except when :rules is provided/,
                   fn ->
                     RequiredColumns.validate(target,
                       rules: [[columns: ["tenant_id"]]],
                       except: [[table: "schema_migrations"]]
                     )
                   end
    end

    test "requires columns to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns :columns to be a non-empty list of strings/,
                   fn ->
                     RequiredColumns.validate(target, columns: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected required_columns :columns to be a non-empty list of strings/,
                   fn ->
                     RequiredColumns.validate(target, rules: [[columns: [:tenant_id]]])
                   end
    end

    test "requires rules to be a non-empty list of keyword rules" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns :rules to be a non-empty list of keyword rules/,
                   fn ->
                     RequiredColumns.validate(target, rules: [])
                   end
    end

    test "requires matchers to be keyword matchers or non-empty matcher lists" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns :where to be a matcher or non-empty list of matchers/,
                   fn ->
                     RequiredColumns.validate(target,
                       rules: [[where: [], columns: ["tenant_id"]]]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/expected required_columns :except :tables to be a non-empty list of matcher values/,
                   fn ->
                     RequiredColumns.validate(target,
                       columns: ["tenant_id"],
                       except: [[schemas: ["public"]], [tables: [""]]]
                     )
                   end
    end

    test "rejects only as an unknown rule option" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown required_columns rule option: :only/,
                   fn ->
                     RequiredColumns.validate(target,
                       rules: [
                         [
                           only: [tables: ["orders"]],
                           columns: ["tenant_id"]
                         ]
                       ]
                     )
                   end
    end

    test "rejects singular matcher keys and requires matcher values to be non-empty lists" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown required_columns :where matcher option: :schema/,
                   fn ->
                     RequiredColumns.validate(target,
                       rules: [[where: [schema: ["public"]], columns: ["tenant_id"]]]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/expected required_columns :where :schemas to be a non-empty list of matcher values/,
                   fn ->
                     RequiredColumns.validate(target,
                       rules: [[where: [schemas: "public"], columns: ["tenant_id"]]]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/expected required_columns :where :schemas to be a non-empty list of matcher values/,
                   fn ->
                     RequiredColumns.validate(target,
                       rules: [[where: [schemas: []], columns: ["tenant_id"]]]
                     )
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} =
               RequiredColumns.validate(target,
                 rules: [
                   [
                     where: [schemas: ["public"]],
                     columns: ["tenant_id"],
                     except: [[tables: ["schema_migrations"]]]
                   ]
                 ]
               )

      assert issue.message == "could not inspect Postgres table columns"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               rule: %{
                 columns: ["tenant_id"],
                 where: [[schema: ["public"]]],
                 except: [[table: ["schema_migrations"]]]
               },
               except: [],
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        RequiredColumns.validate(target, columns: ["tenant_id"])
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
      columns: ["schema_name", "table_name", "missing_columns"],
      rows: rows
    }
  end
end
