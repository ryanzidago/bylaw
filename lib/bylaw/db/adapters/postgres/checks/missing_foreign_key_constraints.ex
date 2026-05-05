defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints do
  @moduledoc """
  Flags Postgres columns that look like foreign keys but have no constraint.

  By default the check inspects all non-system schemas in a Postgres target.
  Pass `:schemas` or `:tables` options to narrow the scope. A column is treated
  as a candidate when it ends in `_id`, is not named `id`, is not part of a
  primary key, and is not covered by a declared foreign key constraint.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @query """
  SELECT
    namespace.nspname AS schema_name,
    table_class.relname AS table_name,
    attribute.attname AS column_name
  FROM pg_catalog.pg_attribute AS attribute
  JOIN pg_catalog.pg_class AS table_class
    ON table_class.oid = attribute.attrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = table_class.relnamespace
  WHERE table_class.relkind IN ('r', 'p')
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped
    AND attribute.attname <> 'id'
    AND attribute.attname LIKE '%\\_id' ESCAPE '\\'
    AND namespace.nspname <> 'information_schema'
    AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
    AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
    AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_record
      WHERE constraint_record.conrelid = table_class.oid
        AND constraint_record.contype = 'f'
        AND attribute.attnum = ANY(constraint_record.conkey)
    )
    AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS constraint_record
      WHERE constraint_record.conrelid = table_class.oid
        AND constraint_record.contype = 'p'
        AND attribute.attnum = ANY(constraint_record.conkey)
    )
  ORDER BY schema_name, table_name, column_name
  """

  @type check_opt ::
          {:validate, boolean()}
          | {:schemas, list(String.t())}
          | {:tables, list(String.t())}

  @type check_opts :: list(check_opt())

  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "column_name" => :column_name,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Validates that foreign-key-shaped columns have foreign key constraints.

  The check is enabled by default. Pass `validate: false` to skip it. Use
  `schemas: [...]` or `tables: [...]` to narrow the default all-schema scope.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_missing_foreign_key_constraints(target, opts)
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

  defp validate_missing_foreign_key_constraints(target, opts) do
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
            "expected missing_foreign_key_constraints opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :schemas, :tables]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown missing_foreign_key_constraints option: #{inspect(key)}"
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

  @spec issue(target :: Target.t(), row :: result_row()) :: Issue.t()
  defp issue(target, row) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    column_name = value(row, "column_name")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected #{schema_name}.#{table_name}.#{column_name} to declare a foreign key constraint",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        column: column_name
      }
    }
  end

  @spec query_error_issue(
          target :: Target.t(),
          schemas :: list(String.t()) | nil,
          tables :: list(String.t()) | nil,
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, schemas, tables, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres foreign key candidate columns",
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
