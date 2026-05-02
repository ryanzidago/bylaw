defmodule Bylaw.Db.Postgres.Checks.ForeignKeyIndexes do
  @moduledoc """
  Validates that Postgres foreign keys have supporting indexes.

  The check inspects one target schema. A foreign key passes when the referencing
  table has a valid, non-partial index whose leading columns contain the foreign
  key columns.
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
      AND namespace.nspname = $1
  ) AS foreign_key
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_record
    WHERE index_record.indrelid = foreign_key.table_oid
      AND index_record.indisvalid
      AND index_record.indpred IS NULL
      AND foreign_key.key_attnums <@
        index_record.indkey[0:array_length(foreign_key.key_attnums, 1) - 1]
  )
  ORDER BY schema_name, table_name, constraint_name
  """

  @type check_opts :: list({:validate, boolean()})
  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "column_names" => :column_names,
    "constraint_name" => :constraint_name,
    "table_name" => :table_name
  }

  @doc """
  Returns the option namespace used by this check.
  """

  @impl Bylaw.Db.Check
  @spec name() :: :foreign_key_indexes
  def name, do: :foreign_key_indexes

  @doc """
  Validates that foreign keys in the target schema have supporting indexes.

  The check is enabled by default. Pass `validate: false` to skip it.
  """

  @impl Bylaw.Db.Check
  @spec validate(Target.t(), check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == false do
      :ok
    else
      validate_foreign_key_indexes(target)
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

  defp validate_foreign_key_indexes(target) do
    case Postgres.query(target, @query, [target.schema], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.map(&issue(target, &1))
        |> result()

      {:error, reason} ->
        {:error, query_error_issue(target, reason)}
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
    unless Keyword.keyword?(opts) do
      raise ArgumentError,
            "expected foreign_key_indexes opts to be a keyword list, got: #{inspect(opts)}"
    end

    Enum.each(opts, fn {key, _value} ->
      if key != :validate do
        raise ArgumentError, "unknown foreign_key_indexes option: #{inspect(key)}"
      end
    end)

    opts
  end

  @spec issue(Target.t(), result_row()) :: Issue.t()
  defp issue(target, row) do
    table_name = value(row, "table_name")
    constraint_name = value(row, "constraint_name")
    column_names = value(row, "column_names")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected foreign key #{constraint_name} on #{target.schema}.#{table_name} to have a supporting index",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: target.schema,
        table: table_name,
        constraint: constraint_name,
        columns: column_names
      }
    }
  end

  @spec query_error_issue(Target.t(), term()) :: Issue.t()
  defp query_error_issue(target, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres foreign keys for #{target.schema}",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: target.schema,
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
