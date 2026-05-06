defmodule Bylaw.Db.Adapters.Postgres.Result do
  @moduledoc false

  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue

  @typedoc false
  @type row :: %{optional(String.t()) => term(), optional(atom()) => term()}

  @doc false
  @spec rows(map() | list(row())) :: list(row())
  def rows(result) when is_map(result) do
    %{columns: columns, rows: rows} = result

    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  def rows(rows) when is_list(rows), do: rows

  @doc false
  @spec to_check_result(list(Issue.t())) :: Check.result()
  def to_check_result([]), do: :ok
  def to_check_result(issues), do: {:error, issues}

  @doc false
  @spec value(row(), String.t(), %{String.t() => atom()}) :: term()
  def value(row, key, row_keys) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(row, Map.fetch!(row_keys, key))
    end
  end
end
