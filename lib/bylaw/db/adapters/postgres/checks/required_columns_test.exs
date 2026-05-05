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

      assert_received {:query, sql, [["tenant_id", "account_id"], nil, nil, nil, nil, nil], []}
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
               missing_columns: ["tenant_id", "account_id"]
             }
    end

    test "passes filters and escape hatches as check scope" do
      target = target({:ok, result([])})

      assert :ok =
               RequiredColumns.validate(target,
                 columns: ["tenant_id"],
                 schemas: ["public", "billing"],
                 tables: ["orders", "line_items"],
                 except_tables: ["schema_migrations"],
                 except_table_refs: [{"public", "orders"}]
               )

      assert_received {:query, _sql,
                       [
                         ["tenant_id"],
                         ["public", "billing"],
                         ["orders", "line_items"],
                         ["schema_migrations"],
                         ["public"],
                         ["orders"]
                       ], []}
    end

    test "returns every required column issue" do
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

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns opts to be a keyword list/,
                   fn ->
                     RequiredColumns.validate(target, [:not_keyword])
                   end
    end

    test "requires columns when validation is enabled" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns :columns to be a non-empty list of strings/,
                   fn ->
                     RequiredColumns.validate(target, [])
                   end
    end

    test "requires filter options to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns :columns to be a non-empty list of strings/,
                   fn ->
                     RequiredColumns.validate(target, columns: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected required_columns :schemas to be a non-empty list of strings/,
                   fn ->
                     RequiredColumns.validate(target, columns: ["tenant_id"], schemas: [:public])
                   end

      assert_raise ArgumentError,
                   ~r/expected required_columns :except_tables to be a non-empty list of strings/,
                   fn ->
                     RequiredColumns.validate(target, columns: ["tenant_id"], except_tables: [""])
                   end
    end

    test "requires except table refs to be string tuples" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected required_columns :except_table_refs to be a list of {schema, table} string tuples/,
                   fn ->
                     RequiredColumns.validate(target,
                       columns: ["tenant_id"],
                       except_table_refs: [{"public", ""}]
                     )
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} =
               RequiredColumns.validate(target,
                 columns: ["tenant_id"],
                 schemas: ["public"],
                 tables: ["orders"],
                 except_tables: ["schema_migrations"],
                 except_table_refs: [{"public", "audit_log"}]
               )

      assert issue.message == "could not inspect Postgres table columns"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               columns: ["tenant_id"],
               schemas: ["public"],
               tables: ["orders"],
               except_tables: ["schema_migrations"],
               except_table_refs: [{"public", "audit_log"}],
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
