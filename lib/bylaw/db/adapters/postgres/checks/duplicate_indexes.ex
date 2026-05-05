defmodule Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes do
  @moduledoc """
  Flags equivalent Postgres indexes on the same table.

  By default the check inspects all non-system schemas in a Postgres target.
  Pass `:schemas` or `:tables` options to narrow the scope. Indexes are treated
  as duplicates when they have the same table, access method, uniqueness,
  validity, key and included columns, operator classes, collations, sort options,
  expressions, and predicate.
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
    index_names
  FROM (
    SELECT
      namespace.nspname AS schema_name,
      table_class.relname AS table_name,
      ARRAY_AGG(index_class.relname ORDER BY index_class.relname) AS index_names,
      COUNT(*) AS index_count
    FROM pg_catalog.pg_index AS index_record
    JOIN pg_catalog.pg_class AS table_class
      ON table_class.oid = index_record.indrelid
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = table_class.relnamespace
    JOIN pg_catalog.pg_class AS index_class
      ON index_class.oid = index_record.indexrelid
    JOIN pg_catalog.pg_am AS access_method
      ON access_method.oid = index_class.relam
    WHERE table_class.relkind IN ('r', 'p')
      AND namespace.nspname <> 'information_schema'
      AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
      AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
      AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
    GROUP BY
      namespace.nspname,
      table_class.relname,
      table_class.oid,
      access_method.amname,
      index_record.indisunique,
      index_record.indisvalid,
      index_record.indnkeyatts,
      index_record.indkey,
      index_record.indclass,
      index_record.indcollation,
      index_record.indoption,
      pg_catalog.pg_get_expr(index_record.indexprs, index_record.indrelid),
      pg_catalog.pg_get_expr(index_record.indpred, index_record.indrelid)
  ) AS duplicate_group
  WHERE index_count > 1
  ORDER BY schema_name, table_name, index_names
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
    "index_names" => :index_names,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Returns the option namespace used by this check.
  """
  @impl Bylaw.Db.Check
  @spec name() :: :duplicate_indexes
  def name, do: :duplicate_indexes

  @doc """
  Validates that tables do not have duplicate indexes.

  The check is enabled by default. Pass `validate: false` to skip it. Use
  `schemas: [...]` or `tables: [...]` to narrow the default all-schema scope.
  """
  @impl Bylaw.Db.Check
  @spec validate(Target.t(), check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_duplicate_indexes(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected duplicate_indexes opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_duplicate_indexes(target, opts) do
    schemas = filter(opts, :schemas)
    tables = filter(opts, :tables)

    case Postgres.query(target, @query, [schemas, tables], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.map(&issue(target, &1))
        |> result()

      {:error, reason} ->
        {:error, [query_error_issue(target, schemas, tables, reason)]}
    end
  end

  defp rows(result) when is_map(result) do
    %{columns: columns, rows: rows} = result

    Enum.map(rows, fn row ->
      columns
      |> Enum.zip(row)
      |> Map.new()
    end)
  end

  defp rows(rows) when is_list(rows), do: rows

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}

  defp check_opts!(opts) do
    if not Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected duplicate_indexes opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :schemas, :tables]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown duplicate_indexes option: #{inspect(key)}"
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
              "expected duplicate_indexes #{inspect(key)} to be a boolean, got: #{inspect(value)}"

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
          "expected duplicate_indexes #{inspect(key)} to be a non-empty list of strings"
  end

  @spec issue(Target.t(), result_row()) :: Issue.t()
  defp issue(target, row) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    index_names = value(row, "index_names")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected #{schema_name}.#{table_name} to have no duplicate indexes, found #{Enum.join(index_names, ", ")}",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        indexes: index_names
      }
    }
  end

  @spec query_error_issue(Target.t(), list(String.t()) | nil, list(String.t()) | nil, term()) ::
          Issue.t()
  defp query_error_issue(target, schemas, tables, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres indexes",
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
