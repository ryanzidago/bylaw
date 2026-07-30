defmodule Bylaw.Db.Adapters.Postgres.ResultPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bylaw.Db.Adapters.Postgres.Result

  property "normalized rows preserve every column and value association" do
    check all(
            columns <-
              uniq_list_of(string(:alphanumeric, min_length: 1, max_length: 20), max_length: 8),
            values <- fixed_list(Enum.map(columns, fn _column -> term() end))
          ) do
      result = %{columns: columns, rows: [values]}

      assert Result.rows(result) == [Map.new(Enum.zip(columns, values))]
    end
  end
end
