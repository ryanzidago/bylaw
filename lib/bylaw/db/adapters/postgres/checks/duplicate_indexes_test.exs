defmodule Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexesTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "passes when no duplicate indexes exist" do
      target = target({:ok, result([])})

      assert :ok = DuplicateIndexes.validate(target, [])

      assert_received {:query, "ecto_psql_extras.duplicate_indexes", [], []}
    end

    test "returns an issue for duplicate indexes" do
      target =
        target(
          {:ok,
           result([
             ["16 kB", "orders_user_id_idx", "orders_user_id_duplicate_idx", nil, nil]
           ])}
        )

      assert {:error, [%Issue{} = issue]} = DuplicateIndexes.validate(target, [])

      assert issue.check == DuplicateIndexes
      assert issue.target == target

      assert issue.message ==
               "expected duplicate indexes orders_user_id_idx, orders_user_id_duplicate_idx to be consolidated"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               size: "16 kB",
               indexes: ["orders_user_id_idx", "orders_user_id_duplicate_idx"],
               source: :ecto_psql_extras
             }
    end

    test "accepts query results that are already maps" do
      target =
        target(
          {:ok,
           [
             %{
               size: "16 kB",
               idx1: "orders_user_id_idx",
               idx2: "orders_user_id_duplicate_idx",
               idx3: nil,
               idx4: nil
             }
           ]}
        )

      assert {:error, [%Issue{} = issue]} = DuplicateIndexes.validate(target, [])

      assert issue.meta.indexes == ["orders_user_id_idx", "orders_user_id_duplicate_idx"]
    end

    test "skips validation when disabled" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts -> flunk("query should not run") end
        )

      assert :ok = DuplicateIndexes.validate(target, validate: false)
    end

    test "rejects unknown options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError, ~r/unknown duplicate_indexes option: :unknown/, fn ->
        DuplicateIndexes.validate(target, unknown: true)
      end
    end

    test "requires keyword options" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected duplicate_indexes opts to be a keyword list/,
                   fn ->
                     DuplicateIndexes.validate(target, [:not_keyword])
                   end
    end

    test "requires validate option to be a boolean" do
      target = target({:ok, result([])})

      assert_raise ArgumentError,
                   ~r/expected duplicate_indexes :validate to be a boolean/,
                   fn ->
                     DuplicateIndexes.validate(target, validate: :yes)
                   end
    end

    test "returns an issue when introspection fails" do
      target = target({:error, :connection_closed})

      assert {:error, [%Issue{} = issue]} = DuplicateIndexes.validate(target, [])

      assert issue.message == "could not inspect Postgres duplicate indexes"

      assert issue.meta == %{
               repo: nil,
               dynamic_repo: nil,
               reason: :connection_closed
             }
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        DuplicateIndexes.validate(target, [])
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
      columns: ["size", "idx1", "idx2", "idx3", "idx4"],
      rows: rows
    }
  end
end
