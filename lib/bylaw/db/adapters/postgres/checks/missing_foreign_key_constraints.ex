defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints do
  @moduledoc """
  Validates that foreign key-like Postgres columns have foreign key constraints.

  By default the check uses `ecto_psql_extras` to inspect all non-system tables
  in a Postgres target. Pass `:tables` to narrow the scope. The underlying
  detection is convention-based: columns that look like foreign keys should have
  database foreign key constraints.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.EctoPsqlExtras
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:tables, list(String.t())}
          )
  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "column_name" => :column_name,
    "table" => :table
  }

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Db.Check
  @spec name() :: :missing_foreign_key_constraints
  def name, do: :missing_foreign_key_constraints

  @doc """
  Validates that foreign key-like columns in the target scope have constraints.

  The check is enabled by default. Pass `validate: false` to skip it. Use
  `tables: [...]` to narrow the default all-table scope.
  """

  @impl Bylaw.Db.Check
  @spec validate(Target.t(), check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_missing_constraints(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected missing_foreign_key_constraints opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_missing_constraints(target, opts) do
    tables = filter(opts, :tables)

    case missing_constraint_rows(target, tables) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.uniq_by(&row_key/1)
        |> Enum.map(&issue(target, &1))
        |> result()

      {:error, reason} ->
        {:error, [query_error_issue(target, tables, reason)]}
    end
  end

  defp missing_constraint_rows(%Target{} = target, tables) do
    tables
    |> table_names()
    |> Enum.reduce_while({:ok, []}, fn table_name, {:ok, rows} ->
      case EctoPsqlExtras.query(
             target,
             :missing_fk_constraints,
             missing_fk_constraints_opts(table_name),
             [table_name]
           ) do
        {:ok, result} -> {:cont, {:ok, rows ++ result_rows(result)}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp result_rows(result) when is_map(result) do
    case Map.fetch(result, :rows) do
      {:ok, rows} -> rows
      :error -> Map.fetch!(result, "rows")
    end
  end

  defp result_rows(rows) when is_list(rows), do: rows

  defp table_names(nil), do: [nil]
  defp table_names(tables), do: tables

  defp missing_fk_constraints_opts(nil), do: [format: :raw]

  defp missing_fk_constraints_opts(table_name),
    do: [format: :raw, args: [table_name: table_name]]

  defp rows(result) when is_map(result) do
    %{columns: columns, rows: rows} = result

    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  defp rows(rows) when is_list(rows) do
    Enum.map(rows, fn
      [table_name, column_name] -> %{"table" => table_name, "column_name" => column_name}
      row -> row
    end)
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp check_opts!(opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected missing_foreign_key_constraints opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :tables]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown missing_foreign_key_constraints option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)
    validate_filter_option!(opts, :tables)

    opts
  end

  defp validate_boolean_option!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_boolean(value) ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "expected missing_foreign_key_constraints #{inspect(key)} to be a boolean, got: #{inspect(value)}"

      :error ->
        :ok
    end
  end

  defp validate_filter_option!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, values} ->
        filter!(key, values)
        :ok

      :error ->
        :ok
    end
  end

  defp filter(opts, key) do
    values = Keyword.get(opts, key)

    filter!(key, values)
  end

  defp filter!(_key, nil), do: nil

  defp filter!(key, values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_filter_error!(key)
    end

    values
  end

  defp filter!(key, _values), do: raise_filter_error!(key)

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_filter_error!(key) do
    raise ArgumentError,
          "expected missing_foreign_key_constraints #{inspect(key)} to be a non-empty list of strings"
  end

  @spec issue(Target.t(), result_row()) :: Issue.t()
  defp issue(target, row) do
    table_name = value(row, "table")
    column_name = value(row, "column_name")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected foreign key-like column #{column_name} on #{table_name} to have a foreign key constraint",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        table: table_name,
        column: column_name,
        source: :ecto_psql_extras
      }
    }
  end

  @spec query_error_issue(Target.t(), list(String.t()) | nil, term()) :: Issue.t()
  defp query_error_issue(target, tables, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres foreign key constraints",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        tables: tables,
        reason: reason
      }
    }
  end

  defp value(row, key) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(row, Map.fetch!(@row_keys, key))
    end
  end

  defp row_key(row), do: {value(row, "table"), value(row, "column_name")}
end
