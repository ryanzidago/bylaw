defmodule Bylaw.Db.Adapters.Postgres.Checks.ForbiddenColumnTypesTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.ForbiddenColumnTypes
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when no columns use forbidden types" do
      target = target({:ok, result([["public", "events", "payload", "jsonb"]])})

      assert :ok = ForbiddenColumnTypes.validate(target, types: ["json"])

      assert_received {:query, sql, [nil, nil], []}
      assert sql =~ "pg_catalog.format_type(attribute.atttypid, attribute.atttypmod)"
      assert sql =~ "table_class.relkind IN ('r', 'p')"
      assert sql =~ "NOT attribute.attisdropped"
    end

    test "reports exact forbidden types" do
      target = target({:ok, result([["public", "events", "payload", "json"]])})

      assert {:error, [%Issue{} = issue]} = ForbiddenColumnTypes.validate(target, types: ["json"])

      assert issue.check == ForbiddenColumnTypes
      assert issue.target == target

      assert issue.message ==
               "expected public.events.payload not to use forbidden type json"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               schema: "public",
               table: "events",
               column: "payload",
               type: "json",
               matched_type: "json",
               prefer: nil,
               reason: nil
             }
    end

    test "reports regex forbidden types" do
      target =
        target({:ok, result([["public", "profiles", "name", "character varying(255)"]])})

      assert {:error, [%Issue{} = issue]} =
               ForbiddenColumnTypes.validate(target, types: [~r/^character varying/])

      assert issue.meta.type == "character varying(255)"
      assert inspect(issue.meta.matched_type) == inspect(~r/^character varying/)
    end

    test "reports educational keyword rules" do
      target = target({:ok, result([["public", "events", "payload", "json"]])})

      assert {:error, [%Issue{} = issue]} =
               ForbiddenColumnTypes.validate(target,
                 types: [
                   [
                     type: "json",
                     prefer: "jsonb",
                     reason:
                       "jsonb is indexable and avoids reparsing for most application queries"
                   ]
                 ]
               )

      assert issue.message ==
               "expected public.events.payload not to use forbidden type json; prefer jsonb because jsonb is indexable and avoids reparsing for most application queries"

      assert issue.meta.prefer == "jsonb"

      assert issue.meta.reason ==
               "jsonb is indexable and avoids reparsing for most application queries"
    end

    test "supports multiple forbidden type rules" do
      target =
        target(
          {:ok,
           result([
             ["public", "events", "payload", "json"],
             ["public", "payments", "amount", "money"],
             ["public", "profiles", "name", "character(8)"]
           ])}
        )

      assert {:error, issues} =
               ForbiddenColumnTypes.validate(target,
                 types: [
                   "json",
                   [type: "money", prefer: "numeric"],
                   [type: ~r/^character\(/, prefer: "text"]
                 ]
               )

      assert Enum.map(issues, &{&1.meta.table, &1.meta.column, &1.meta.type}) == [
               {"events", "payload", "json"},
               {"payments", "amount", "money"},
               {"profiles", "name", "character(8)"}
             ]
    end

    test "applies rule scope after introspection" do
      target = target({:ok, result([])})

      assert :ok =
               ForbiddenColumnTypes.validate(target,
                 rules: [
                   [
                     where: [
                       schemas: ["public", "billing"],
                       tables: ["events", "payments"]
                     ],
                     types: ["json"]
                   ]
                 ]
               )

      assert_received {:query, _sql, [nil, nil], []}
    end

    test "skips matching exceptions by table column and type" do
      target =
        target(
          {:ok,
           result([
             ["public", "events", "payload", "json"],
             ["public", "events", "metadata", "json"],
             ["public", "payments", "amount", "money"]
           ])}
        )

      assert :ok =
               ForbiddenColumnTypes.validate(target,
                 rules: [
                   [
                     types: ["json", "money"],
                     except: [
                       [tables: ["events"], columns: ["payload"]],
                       [columns: ["metadata"], types: ["json"]],
                       [tables: ["payments"], types: ["money"]]
                     ]
                   ]
                 ]
               )
    end

    test "supports regex exception matchers" do
      target =
        target(
          {:ok,
           result([
             ["public", "webhook_events", "raw_payload", "json"],
             ["public", "legacy_events", "payload", "json"],
             ["public", "payments", "amount", "money"]
           ])}
        )

      assert :ok =
               ForbiddenColumnTypes.validate(target,
                 rules: [
                   [
                     types: ["json", "money"],
                     except: [
                       [tables: [~r/_events$/], columns: [~r/payload$/]],
                       [types: [~r/^money$/]]
                     ]
                   ]
                 ]
               )
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               schema_name: "public",
               table_name: "events",
               column_name: "payload",
               type_name: "json"
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = ForbiddenColumnTypes.validate(target, types: ["json"])

      assert issue.meta.table == "events"
      assert issue.meta.column == "payload"
    end

    test "skips validation when disabled without requiring types" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = ForbiddenColumnTypes.validate(target, validate: false)
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} =
               ForbiddenColumnTypes.validate(target,
                 rules: [
                   [
                     where: [schemas: ["public"], tables: ["events"]],
                     types: ["json"],
                     except: [[tables: ["webhook_events"]]]
                   ]
                 ]
               )

      assert issue.message == "could not inspect Postgres column types"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               rules: [
                 %{
                   where: [[schema: ["public"], table: ["events"]]],
                   types: [%{type: "json", prefer: nil, reason: nil}],
                   except: [[table: ["webhook_events"]]]
                 }
               ],
               reason: :connection_closed
             }
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown forbidden_column_types option: :unknown/, fn ->
        ForbiddenColumnTypes.validate(target, types: ["json"], unknown: true)
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types opts to be a keyword list/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, [:not_keyword])
                   end
    end

    test "requires options to be a list" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types opts to be a keyword list/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, :not_a_list)
                   end
    end

    test "requires types when validation is enabled" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/expected forbidden_column_types to include :types/, fn ->
        ForbiddenColumnTypes.validate(target, [])
      end
    end

    test "requires types to be non-empty valid type rules" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types :types to be a non-empty list/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, types: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types :types to be a non-empty list/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, types: [:json])
                   end
    end

    test "requires keyword type rules to include type" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types type rule to include :type/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, types: [[prefer: "jsonb"]])
                   end
    end

    test "requires prefer to be a non-empty string" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types type rule :prefer to be a non-empty string/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, types: [[type: "json", prefer: ""]])
                   end
    end

    test "requires reason to be a non-empty string" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types type rule :reason to be a non-empty string/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, types: [[type: "json", reason: :bad]])
                   end
    end

    test "rejects top-level scope options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/unknown forbidden_column_types option: :schemas/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, types: ["json"], schemas: [])
                   end

      assert_raise ArgumentError,
                   ~r/unknown forbidden_column_types option: :tables/,
                   fn ->
                     ForbiddenColumnTypes.validate(target, types: ["json"], tables: [""])
                   end
    end

    test "requires rule exceptions to be matchers" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types :except to be a matcher or non-empty list of matchers/,
                   fn ->
                     ForbiddenColumnTypes.validate(target,
                       rules: [[types: ["json"], except: ["events"]]]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/unknown forbidden_column_types :except matcher option: :unknown/,
                   fn ->
                     ForbiddenColumnTypes.validate(target,
                       rules: [[types: ["json"], except: [unknown: "events"]]]
                     )
                   end

      assert_raise ArgumentError,
                   ~r/expected forbidden_column_types :except :types to be a non-empty list of matcher values/,
                   fn ->
                     ForbiddenColumnTypes.validate(target,
                       rules: [[types: ["json"], except: [types: []]]]
                     )
                   end
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        ForbiddenColumnTypes.validate(target, types: ["json"])
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
      columns: ["schema_name", "table_name", "column_name", "type_name"],
      rows: rows
    }
  end
end
