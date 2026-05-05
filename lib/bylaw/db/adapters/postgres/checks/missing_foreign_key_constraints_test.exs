defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraintsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when every foreign key-like column has a constraint" do
      target = target({:ok, result([])})

      assert :ok = MissingForeignKeyConstraints.validate(target, [])

      assert_received {:query, "ecto_psql_extras.missing_fk_constraints", [nil], []}
    end

    test "returns an issue when one foreign key-like column is missing a constraint" do
      target =
        target(
          {:ok,
           result([
             ["orders", "user_id"]
           ])}
        )

      assert {:error, [%Issue{} = issue]} =
               MissingForeignKeyConstraints.validate(target, [])

      assert issue.check == MissingForeignKeyConstraints
      assert issue.target == target

      assert issue.message ==
               "expected foreign key-like column user_id on orders to have a foreign key constraint"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               table: "orders",
               column: "user_id",
               source: :ecto_psql_extras
             }
    end

    test "passes table filters as check scope" do
      target = target({:ok, result([])})

      assert :ok =
               MissingForeignKeyConstraints.validate(target,
                 tables: ["orders", "line_items"]
               )

      assert_received {:query, _sql, ["orders"], []}
      assert_received {:query, _sql, ["line_items"], []}
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

      assert {:error, [%Issue{} = issue]} = MissingForeignKeyConstraints.validate(target, [])

      assert issue.meta.table == "orders"
      assert issue.meta.column == "user_id"
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

    test "requires table filters to be non-empty lists of strings" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected missing_foreign_key_constraints :tables to be a non-empty list of strings/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, tables: [])
                   end

      assert_raise ArgumentError,
                   ~r/expected missing_foreign_key_constraints :tables to be a non-empty list of strings/,
                   fn ->
                     MissingForeignKeyConstraints.validate(target, tables: [""])
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} = MissingForeignKeyConstraints.validate(target, [])

      assert issue.message == "could not inspect Postgres foreign key constraints"

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
      columns: ["table", "column_name"],
      rows: rows
    }
  end
end
