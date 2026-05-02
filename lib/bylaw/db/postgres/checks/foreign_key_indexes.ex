defmodule Bylaw.Db.Postgres.Checks.ForeignKeyIndexes do
  @moduledoc """
  Validates that Postgres foreign keys have supporting indexes.

  By default the check inspects all non-system schemas in a Postgres target.
  Pass `:schemas` or `:tables` options to narrow the scope. A foreign key passes
  when the referencing table has a valid, non-partial index whose leading
  columns contain the foreign key columns.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @query """
  SELECT
    schema_name,
    table_name,
    constraint_name,
    column_names
  FROM (
    SELECT
      namespace.nspname AS schema_name,
      table_class.relname AS table_name,
      constraint_record.conname AS constraint_name,
      constraint_record.conrelid AS table_oid,
      constraint_record.conkey AS key_attnums,
      ARRAY(
        SELECT attribute.attname
        FROM unnest(constraint_record.conkey) WITH ORDINALITY AS key(attnum, position)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_record.conrelid
         AND attribute.attnum = key.attnum
        ORDER BY key.position
      ) AS column_names
    FROM pg_catalog.pg_constraint AS constraint_record
    JOIN pg_catalog.pg_class AS table_class
      ON table_class.oid = constraint_record.conrelid
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = table_class.relnamespace
    WHERE constraint_record.contype = 'f'
      AND namespace.nspname <> 'information_schema'
      AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
      AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
      AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
  ) AS foreign_key
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_record
    WHERE index_record.indrelid = foreign_key.table_oid
      AND index_record.indisvalid
      AND index_record.indpred IS NULL
      AND index_record.indnkeyatts >= array_length(foreign_key.key_attnums, 1)
      AND foreign_key.key_attnums <@
        index_record.indkey[0:array_length(foreign_key.key_attnums, 1) - 1]
  )
  ORDER BY schema_name, table_name, constraint_name
  """

  @type check_opts ::
          list(
            {:validate, boolean()}
            | {:schemas, list(String.t())}
            | {:tables, list(String.t())}
          )
  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "column_names" => :column_names,
    "constraint_name" => :constraint_name,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Db.Check
  @spec name() :: :foreign_key_indexes
  def name, do: :foreign_key_indexes

  @doc """
  Validates that foreign keys in the target scope have supporting indexes.

  The check is enabled by default. Pass `validate: false` to skip it. Use
  `schemas: [...]` or `tables: [...]` to narrow the default all-schema scope.
  """

  @impl Bylaw.Db.Check
  @spec validate(Target.t(), check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == false do
      :ok
    else
      validate_foreign_key_indexes(target, opts)
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected foreign_key_indexes opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_foreign_key_indexes(target, opts) do
    schemas = filter(opts, :schemas)
    tables = filter(opts, :tables)

    case Postgres.query(target, @query, [schemas, tables], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.map(&issue(target, &1))
        |> result()

      {:error, reason} ->
        {:error, query_error_issue(target, schemas, tables, reason)}
    end
  end

  defp rows(%{columns: columns, rows: rows}) do
    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  defp rows(rows) when is_list(rows), do: rows

  defp result([]), do: :ok
  defp result([issue]), do: {:error, issue}
  defp result(issues), do: {:error, issues}

  defp check_opts!(opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected foreign_key_indexes opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :schemas, :tables]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown foreign_key_indexes option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)
    validate_filter_option!(opts, :schemas)
    validate_filter_option!(opts, :tables)

    opts
  end

  defp validate_boolean_option!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_boolean(value) ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "expected foreign_key_indexes #{inspect(key)} to be a boolean, got: #{inspect(value)}"

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
    opts
    |> Keyword.get(key)
    |> then(&filter!(key, &1))
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
          "expected foreign_key_indexes #{inspect(key)} to be a non-empty list of strings"
  end

  @spec issue(Target.t(), result_row()) :: Issue.t()
  defp issue(target, row) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    constraint_name = value(row, "constraint_name")
    column_names = value(row, "column_names")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected foreign key #{constraint_name} on #{schema_name}.#{table_name} to have a supporting index",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        constraint: constraint_name,
        columns: column_names
      }
    }
  end

  @spec query_error_issue(Target.t(), list(String.t()) | nil, list(String.t()) | nil, term()) ::
          Issue.t()
  defp query_error_issue(target, schemas, tables, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres foreign keys",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schemas: schemas,
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
end
