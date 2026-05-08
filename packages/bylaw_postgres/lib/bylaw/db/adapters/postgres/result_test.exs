defmodule Bylaw.Db.Adapters.Postgres.ResultTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres.Result
  alias Bylaw.Db.Issue

  describe "rows/1" do
    test "converts an Ecto SQL result map into row maps" do
      result = %{
        columns: ["schema_name", "table_name"],
        rows: [["public", "orders"], ["billing", "invoices"]]
      }

      assert Result.rows(result) == [
               %{"schema_name" => "public", "table_name" => "orders"},
               %{"schema_name" => "billing", "table_name" => "invoices"}
             ]
    end

    test "returns already normalized row lists" do
      rows = [%{schema_name: "public", table_name: "orders"}]

      assert Result.rows(rows) == rows
    end
  end

  describe "to_check_result/1" do
    test "returns ok for no issues" do
      assert Result.to_check_result([]) == :ok
    end

    test "wraps issues in an error tuple" do
      issues = [%Issue{message: "missing index"}]

      assert Result.to_check_result(issues) == {:error, issues}
    end
  end

  describe "value/3" do
    test "reads string-keyed rows first" do
      row = %{"schema_name" => "public", schema_name: "billing"}

      assert Result.value(row, "schema_name", %{"schema_name" => :schema_name}) == "public"
    end

    test "falls back to the configured atom key" do
      row = %{schema_name: "public"}

      assert Result.value(row, "schema_name", %{"schema_name" => :schema_name}) == "public"
    end
  end
end
