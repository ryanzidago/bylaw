defmodule Bylaw.Db.Adapters.Postgres.ResultPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bylaw.Db.Adapters.Postgres.Result

  property "normalized rows preserve every column and value association" do
    check all(
            columns <-
              uniq_list_of(string(:alphanumeric, min_length: 1, max_length: 20), max_length: 8),
            rows <-
              list_of(
                fixed_list(Enum.map(columns, fn _column -> term() end)),
                max_length: 8
              )
          ) do
      result = %{columns: columns, rows: rows}

      assert Result.rows(result) ==
               Enum.map(rows, &Map.new(Enum.zip(columns, &1)))
    end
  end
end
