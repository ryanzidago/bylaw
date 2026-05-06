defmodule Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeysTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeys
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every scoped foreign key includes scope columns" do
      target = target({:ok, result([])})

      assert :ok = ScopedForeignKeys.validate(target, scope_columns: ["tenant_id"])

      assert_received {:query, sql, [nil, nil, ["tenant_id"]], []}
      assert sql =~ "pg_catalog.pg_constraint"
      assert sql =~ "pg_catalog.pg_attribute"
      assert sql =~ "referenced_column_names"
    end

    test "returns an issue when a scoped foreign key omits scope columns" do
      target =
        target(
          {:ok,
           result([
             [
               "public",
               "orders",
               "orders_customer_id_fkey",
               ["customer_id"],
               "public",
               "customers",
               ["id"]
             ]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               ScopedForeignKeys.validate(target, scope_columns: ["tenant_id"])

      assert issue.check == ScopedForeignKeys
      assert issue.target == target

      assert issue.message ==
               "expected foreign key orders_customer_id_fkey on public.orders to include required scope columns tenant_id"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "orders",
               constraint: "orders_customer_id_fkey",
               columns: ["customer_id"],
               referenced_schema: "public",
               referenced_table: "customers",
               referenced_columns: ["id"],
               scope_columns: ["tenant_id"]
             }
    end

    test "supports multiple scope columns" do
      target =
        target(
          {:ok,
           result([
             [
               "public",
               "messages",
               "messages_conversation_id_fkey",
               ["conversation_id"],
               "public",
               "conversations",
               ["id"]
             ]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               ScopedForeignKeys.validate(target,
                 scope_columns: ["tenant_id", "workspace_id"]
               )

      assert issue.message =~ "tenant_id, workspace_id"
      assert issue.meta.scope_columns == ["tenant_id", "workspace_id"]
    end

    test "passes schema and table filters as child-table scope" do
      target = target({:ok, result([])})

      assert :ok =
               ScopedForeignKeys.validate(target,
                 scope_columns: ["tenant_id"],
                 schemas: ["public", "billing"],
                 tables: ["orders", "line_items"]
               )

      assert_received {:query, _sql,
                       [["public", "billing"], ["orders", "line_items"], ["tenant_id"]], []}
    end

    test "returns every scoped foreign key issue" do
      target =
        target(
          {:ok,
           result([
             [
               "public",
               "orders",
               "orders_customer_id_fkey",
               ["customer_id"],
               "public",
               "customers",
               ["id"]
             ],
             [
               "public",
               "messages",
               "messages_conversation_id_fkey",
               ["conversation_id"],
               "public",
               "conversations",
               ["id"]
             ]
           ])}
        )

      assert {:error, issues} =
               ScopedForeignKeys.validate(target, scope_columns: ["tenant_id"])

      assert Enum.map(issues, & &1.meta.constraint) == [
               "orders_customer_id_fkey",
               "messages_conversation_id_fkey"
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
               constraint_name: "orders_customer_id_fkey",
               column_names: ["customer_id"],
               referenced_schema_name: "public",
               referenced_table_name: "customers",
               referenced_column_names: ["id"]
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} =
               ScopedForeignKeys.validate(target, scope_columns: ["tenant_id"])

      assert issue.meta.constraint == "orders_customer_id_fkey"
      assert issue.meta.referenced_table == "customers"
    end

    test "skips matching exceptions" do
      target =
        target(
          {:ok,
           result([
             [
               "public",
               "orders",
               "orders_customer_id_fkey",
               ["customer_id"],
               "public",
               "customers",
               ["id"]
             ],
             [
               "public",
               "events",
               "events_global_actor_id_fkey",
               ["global_actor_id"],
               "public",
               "global_actors",
               ["id"]
             ],
             [
               "public",
               "messages",
               "messages_conversation_id_fkey",
               ["conversation_id"],
               "public",
               "conversations",
               ["id"]
             ]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               ScopedForeignKeys.validate(target,
                 scope_columns: ["tenant_id"],
                 except: [
                   [table: "orders", constraint: ~r/customer_id/],
                   [referenced_table: "global_actors"]
                 ]
               )

      assert issue.meta.table == "messages"
      assert issue.meta.referenced_table == "conversations"
    end

    test "skips validation when disabled without requiring scope columns" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = ScopedForeignKeys.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown scoped_foreign_keys option: :unknown/, fn ->
        ScopedForeignKeys.validate(target, scope_columns: ["tenant_id"], unknown: true)
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys opts to be a keyword list/,
                   fn ->
                     ScopedForeignKeys.validate(target, [:not_keyword])
                   end
    end

    test "requires options to be a list" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys opts to be a keyword list/,
                   fn ->
                     ScopedForeignKeys.validate(target, :not_a_list)
                   end
    end

    test "requires scope columns when validation is enabled" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys to include :scope_columns/,
                   fn ->
                     ScopedForeignKeys.validate(target, [])
                   end
    end

    test "requires scope columns to be a non-empty list of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys :scope_columns to be a non-empty list of strings/,
                   fn ->
                     ScopedForeignKeys.validate(target, scope_columns: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys :scope_columns to be a non-empty list of strings/,
                   fn ->
                     ScopedForeignKeys.validate(target, scope_columns: [:tenant_id])
                   end
    end

    test "requires schema filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys :schemas to be a non-empty list of strings/,
                   fn ->
                     ScopedForeignKeys.validate(target,
                       scope_columns: ["tenant_id"],
                       schemas: []
                     )
                   end

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys :schemas to be a non-empty list of strings/,
                   fn ->
                     ScopedForeignKeys.validate(target,
                       scope_columns: ["tenant_id"],
                       schemas: [:public]
                     )
                   end
    end

    test "requires table filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys :tables to be a non-empty list of strings/,
                   fn ->
                     ScopedForeignKeys.validate(target,
                       scope_columns: ["tenant_id"],
                       tables: []
                     )
                   end

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys :tables to be a non-empty list of strings/,
                   fn ->
                     ScopedForeignKeys.validate(target,
                       scope_columns: ["tenant_id"],
                       tables: [""]
                     )
                   end
    end

    test "requires exceptions to be matchers" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys :except to be a matcher or non-empty list of matchers/,
                   fn ->
                     ScopedForeignKeys.validate(target,
                       scope_columns: ["tenant_id"],
                       except: ["orders"]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/unknown scoped_foreign_keys :except matcher option: :unknown/,
                   fn ->
                     ScopedForeignKeys.validate(target,
                       scope_columns: ["tenant_id"],
                       except: [unknown: "orders"]
                     )
                   end
    end

    test "requires plural exception matcher values to be non-empty lists" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected scoped_foreign_keys :except :referenced_tables to be a matcher value or non-empty list of matcher values/,
                   fn ->
                     ScopedForeignKeys.validate(target,
                       scope_columns: ["tenant_id"],
                       except: [referenced_tables: []]
                     )
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} =
               ScopedForeignKeys.validate(target,
                 rules: [
                   [
                     scope_columns: ["tenant_id"],
                     only: [schema: "public", table: "orders"],
                     except: [[referenced_table: "global_settings"]]
                   ]
                 ]
               )

      assert issue.message == "could not inspect Postgres scoped foreign keys"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               rule: %{
                 only: [[schema: "public", table: "orders"]],
                 scope_columns: ["tenant_id"],
                 except: [[referenced_table: "global_settings"]]
               },
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        ScopedForeignKeys.validate(target, scope_columns: ["tenant_id"])
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
      columns: [
        "schema_name",
        "table_name",
        "constraint_name",
        "column_names",
        "referenced_schema_name",
        "referenced_table_name",
        "referenced_column_names"
      ],
      rows: rows
    }
  end
end
