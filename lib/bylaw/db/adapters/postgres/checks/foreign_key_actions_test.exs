defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActionsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActions
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every foreign key uses the configured global actions" do
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
               ["id"],
               "c",
               "a"
             ]
           ])}
        )

      assert :ok = ForeignKeyActions.validate(target, on_delete: :cascade, on_update: :no_action)

      assert_received {:query, sql, [nil, nil], []}
      assert sql =~ "pg_catalog.pg_constraint"
      assert sql =~ "confdeltype"
      assert sql =~ "confupdtype"
    end

    test "returns an issue when delete action is wrong" do
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
               ["id"],
               "a",
               "a"
             ]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               ForeignKeyActions.validate(target, on_delete: :cascade)

      assert issue.check == ForeignKeyActions
      assert issue.target == target

      assert issue.message ==
               "expected foreign key messages_conversation_id_fkey on public.messages to use ON DELETE CASCADE, got: NO ACTION"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "messages",
               constraint: "messages_conversation_id_fkey",
               columns: ["conversation_id"],
               referenced_schema: "public",
               referenced_table: "conversations",
               referenced_columns: ["id"]
             }
    end

    test "returns an issue when update action is wrong" do
      target =
        target(
          {:ok,
           result([
             [
               "public",
               "messages",
               "messages_status_id_fkey",
               ["status_id"],
               "public",
               "lookup_statuses",
               ["id"],
               "r",
               "c"
             ]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               ForeignKeyActions.validate(target, on_update: :restrict)

      assert issue.message ==
               "expected foreign key messages_status_id_fkey on public.messages to use ON UPDATE RESTRICT, got: CASCADE"
    end

    test "emits delete and update issues when both configured actions are wrong" do
      target =
        target(
          {:ok,
           result([
             [
               "public",
               "messages",
               "messages_status_id_fkey",
               ["status_id"],
               "public",
               "lookup_statuses",
               ["id"],
               "a",
               "a"
             ]
           ])}
        )

      assert {:error, issues} =
               ForeignKeyActions.validate(target, on_delete: :restrict, on_update: :restrict)

      assert Enum.map(issues, & &1.message) == [
               "expected foreign key messages_status_id_fkey on public.messages to use ON DELETE RESTRICT, got: NO ACTION",
               "expected foreign key messages_status_id_fkey on public.messages to use ON UPDATE RESTRICT, got: NO ACTION"
             ]
    end

    test "passes schema and table filters as check scope" do
      target = target({:ok, result([])})

      assert :ok =
               ForeignKeyActions.validate(target,
                 schemas: ["public", "billing"],
                 tables: ["messages", "line_items"],
                 on_delete: :cascade
               )

      assert_received {:query, _sql, [["public", "billing"], ["messages", "line_items"]], []}
    end

    test "supports multiple scoped rules that accumulate by match" do
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
               ["id"],
               "a",
               "c"
             ],
             [
               "public",
               "messages",
               "messages_status_id_fkey",
               ["status_id"],
               "public",
               "lookup_statuses",
               ["id"],
               "a",
               "a"
             ],
             [
               "public",
               "events",
               "events_account_fkey",
               ["tenant_id", "account_id"],
               "public",
               "accounts",
               ["tenant_id", "account_id"],
               "c",
               "a"
             ]
           ])}
        )

      assert {:error, issues} =
               ForeignKeyActions.validate(target,
                 rules: [
                   [
                     where: [[table: "messages"], [referenced_table: "conversations"]],
                     on_delete: :cascade
                   ],
                   [
                     where: [referenced_table: "lookup_statuses"],
                     on_delete: :restrict,
                     on_update: :restrict
                   ],
                   [
                     where: [columns: [~r/account_id/], referenced_columns: ["tenant_id"]],
                     on_delete: :cascade
                   ]
                 ]
               )

      assert Enum.map(issues, &{&1.meta.constraint, &1.message}) == [
               {"messages_conversation_id_fkey",
                "expected foreign key messages_conversation_id_fkey on public.messages to use ON DELETE CASCADE, got: NO ACTION"},
               {"messages_status_id_fkey",
                "expected foreign key messages_status_id_fkey on public.messages to use ON DELETE CASCADE, got: NO ACTION"},
               {"messages_status_id_fkey",
                "expected foreign key messages_status_id_fkey on public.messages to use ON DELETE RESTRICT, got: NO ACTION"},
               {"messages_status_id_fkey",
                "expected foreign key messages_status_id_fkey on public.messages to use ON UPDATE RESTRICT, got: NO ACTION"}
             ]
    end

    test "skips matching exceptions" do
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
               ["id"],
               "a",
               "a"
             ],
             [
               "public",
               "events",
               "events_account_fkey",
               ["tenant_id", "account_id"],
               "public",
               "accounts",
               ["tenant_id", "account_id"],
               "a",
               "a"
             ]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               ForeignKeyActions.validate(target,
                 on_delete: :cascade,
                 except: [
                   [table: "messages", referenced_table: "conversations"],
                   [columns: ["tenant_id"], referenced_column: ~r/missing/]
                 ]
               )

      assert issue.meta.constraint == "events_account_fkey"
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               schema_name: "public",
               table_name: "messages",
               constraint_name: "messages_conversation_id_fkey",
               column_names: ["conversation_id"],
               referenced_schema_name: "public",
               referenced_table_name: "conversations",
               referenced_column_names: ["id"],
               delete_action_code: "a",
               update_action_code: "a"
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} =
               ForeignKeyActions.validate(target, on_delete: :cascade)

      assert issue.meta.constraint == "messages_conversation_id_fkey"
      assert issue.meta.referenced_table == "conversations"
    end

    test "skips validation when disabled without requiring actions" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = ForeignKeyActions.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown foreign_key_actions option: :unknown/, fn ->
        ForeignKeyActions.validate(target, on_delete: :cascade, unknown: true)
      end
    end

    test "rejects unknown rule options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown foreign_key_actions rule option: :unknown/, fn ->
        ForeignKeyActions.validate(target,
          rules: [[on_delete: :cascade, unknown: true]]
        )
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions opts to be a keyword list/,
                   fn ->
                     ForeignKeyActions.validate(target, [:not_keyword])
                   end
    end

    test "requires actions or rules when validation is enabled" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions to include :on_delete, :on_update, or :rules/,
                   fn ->
                     ForeignKeyActions.validate(target, [])
                   end
    end

    test "rejects global actions and rules together" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions to include global actions or :rules, not both/,
                   fn ->
                     ForeignKeyActions.validate(target,
                       on_delete: :cascade,
                       rules: [[on_delete: :restrict]]
                     )
                   end
    end

    test "requires actions to be known atoms" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions :on_delete to be one of/,
                   fn ->
                     ForeignKeyActions.validate(target, on_delete: :delete)
                   end

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions :on_update to be one of/,
                   fn ->
                     ForeignKeyActions.validate(target,
                       rules: [[on_update: :update]]
                     )
                   end
    end

    test "requires rules to be non-empty keyword rules with at least one action" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions :rules to be a non-empty list of keyword rules/,
                   fn ->
                     ForeignKeyActions.validate(target, rules: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions rule to include :on_delete or :on_update/,
                   fn ->
                     ForeignKeyActions.validate(target, rules: [[where: [table: "orders"]]])
                   end
    end

    test "requires schema and table filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions :schemas to be a non-empty list of strings/,
                   fn ->
                     ForeignKeyActions.validate(target, schemas: [], on_delete: :cascade)
                   end

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions :tables to be a non-empty list of strings/,
                   fn ->
                     ForeignKeyActions.validate(target, tables: [:orders], on_delete: :cascade)
                   end
    end

    test "requires matchers to be keyword matchers or non-empty matcher lists" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions :where to be a matcher or non-empty list of matchers/,
                   fn ->
                     ForeignKeyActions.validate(target,
                       rules: [[where: [], on_delete: :cascade]]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/unknown foreign_key_actions :except matcher option: :unknown/,
                   fn ->
                     ForeignKeyActions.validate(target,
                       on_delete: :cascade,
                       except: [unknown: "orders"]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/expected foreign_key_actions :where :referenced_tables to be a matcher value or non-empty list of matcher values/,
                   fn ->
                     ForeignKeyActions.validate(target,
                       rules: [[where: [referenced_tables: [""]], on_delete: :cascade]]
                     )
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} =
               ForeignKeyActions.validate(target,
                 rules: [[where: [schema: "public"], on_delete: :cascade]],
                 except: [[table: "schema_migrations"]]
               )

      assert issue.message == "could not inspect Postgres foreign key actions"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schemas: nil,
               tables: nil,
               rules: [%{where: [[schema: "public"]], on_delete: :cascade, on_update: nil}],
               except: [[table: "schema_migrations"]],
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        ForeignKeyActions.validate(target, on_delete: :cascade)
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
        "referenced_column_names",
        "delete_action_code",
        "update_action_code"
      ],
      rows: rows
    }
  end
end
