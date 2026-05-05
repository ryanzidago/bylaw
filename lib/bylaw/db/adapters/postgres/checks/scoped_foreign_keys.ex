defmodule Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeys do
  @moduledoc """
  Validates that scoped Postgres foreign keys include configured scope columns.

  A foreign key is checked when both the child table and referenced table have
  every configured `:scope_columns` column. The foreign key must include those
  columns on both sides so a child row cannot point at a parent row from another
  scope:

      {ScopedForeignKeys,
       scope_columns: ["tenant_id", "workspace_id"],
       except: [[referenced_table: "global_settings"]]}
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @query """
  WITH foreign_keys AS (
    SELECT
      namespace.nspname AS schema_name,
      table_class.relname AS table_name,
      constraint_record.conname AS constraint_name,
      referenced_namespace.nspname AS referenced_schema_name,
      referenced_class.relname AS referenced_table_name,
      constraint_record.conrelid AS table_oid,
      constraint_record.confrelid AS referenced_table_oid,
      ARRAY(
        SELECT attribute.attname::text
        FROM unnest(constraint_record.conkey) WITH ORDINALITY AS key(attnum, position)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_record.conrelid
         AND attribute.attnum = key.attnum
        ORDER BY key.position
      ) AS column_names,
      ARRAY(
        SELECT attribute.attname::text
        FROM unnest(constraint_record.confkey) WITH ORDINALITY AS key(attnum, position)
        JOIN pg_catalog.pg_attribute AS attribute
          ON attribute.attrelid = constraint_record.confrelid
         AND attribute.attnum = key.attnum
        ORDER BY key.position
      ) AS referenced_column_names
    FROM pg_catalog.pg_constraint AS constraint_record
    JOIN pg_catalog.pg_class AS table_class
      ON table_class.oid = constraint_record.conrelid
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = table_class.relnamespace
    JOIN pg_catalog.pg_class AS referenced_class
      ON referenced_class.oid = constraint_record.confrelid
    JOIN pg_catalog.pg_namespace AS referenced_namespace
      ON referenced_namespace.oid = referenced_class.relnamespace
    WHERE constraint_record.contype = 'f'
      AND namespace.nspname <> 'information_schema'
      AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
      AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
      AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
  ),
  scoped_foreign_keys AS (
    SELECT foreign_keys.*
    FROM foreign_keys
    WHERE NOT EXISTS (
      SELECT 1
      FROM unnest($3::text[]) AS scope_column(column_name)
      WHERE NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_attribute AS attribute
        WHERE attribute.attrelid = foreign_keys.table_oid
          AND attribute.attname = scope_column.column_name
          AND attribute.attnum > 0
          AND NOT attribute.attisdropped
      )
    )
      AND NOT EXISTS (
        SELECT 1
        FROM unnest($3::text[]) AS scope_column(column_name)
        WHERE NOT EXISTS (
          SELECT 1
          FROM pg_catalog.pg_attribute AS attribute
          WHERE attribute.attrelid = foreign_keys.referenced_table_oid
            AND attribute.attname = scope_column.column_name
            AND attribute.attnum > 0
            AND NOT attribute.attisdropped
        )
      )
  )
  SELECT
    schema_name,
    table_name,
    constraint_name,
    column_names,
    referenced_schema_name,
    referenced_table_name,
    referenced_column_names
  FROM scoped_foreign_keys
  WHERE NOT (
    column_names @> $3::text[]
    AND referenced_column_names @> $3::text[]
  )
  ORDER BY schema_name, table_name, constraint_name
  """

  @type matcher_value :: String.t() | Regex.t()
  @type matcher_values :: matcher_value() | list(matcher_value())
  @type matcher ::
          list(
            {:schema, matcher_values()}
            | {:schemas, list(matcher_value())}
            | {:table, matcher_values()}
            | {:tables, list(matcher_value())}
            | {:constraint, matcher_values()}
            | {:constraints, list(matcher_value())}
            | {:referenced_table, matcher_values()}
            | {:referenced_tables, list(matcher_value())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:scope_columns, list(String.t())}
          | {:schemas, list(String.t())}
          | {:tables, list(String.t())}
          | {:except, matcher() | list(matcher())}

  @type check_opts :: list(check_opt())

  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "column_names" => :column_names,
    "constraint_name" => :constraint_name,
    "referenced_column_names" => :referenced_column_names,
    "referenced_schema_name" => :referenced_schema_name,
    "referenced_table_name" => :referenced_table_name,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Returns the option namespace used by this check.
  """
  @impl Bylaw.Db.Check
  @spec name() :: :scoped_foreign_keys
  def name, do: :scoped_foreign_keys

  @doc """
  Validates that scoped foreign keys include configured scope columns.

  The check is enabled by default and requires `scope_columns: [...]`. Pass
  `validate: false` to skip it. Use `schemas: [...]` or `tables: [...]` to
  narrow child-table scope, and `except: [...]` for intentionally global
  references.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_scoped_foreign_keys(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected scoped_foreign_keys opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_scoped_foreign_keys(target, opts) do
    schemas = filter(opts, :schemas)
    tables = filter(opts, :tables)
    scope_columns = scope_columns!(Keyword.fetch!(opts, :scope_columns))
    exceptions = matchers(opts, :except)

    case Postgres.query(target, @query, [schemas, tables, scope_columns], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.reject(&matches_any?(&1, exceptions))
        |> Enum.map(&issue(target, &1, scope_columns))
        |> result()

      {:error, reason} ->
        {:error, [query_error_issue(target, schemas, tables, scope_columns, exceptions, reason)]}
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
            "expected scoped_foreign_keys opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :scope_columns, :schemas, :tables, :except]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown scoped_foreign_keys option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)
    validate_filter_option!(opts, :schemas)
    validate_filter_option!(opts, :tables)

    if Keyword.get(opts, :validate, true) == true do
      if not Keyword.has_key?(opts, :scope_columns) do
        raise ArgumentError, "expected scoped_foreign_keys to include :scope_columns"
      end

      scope_columns!(Keyword.fetch!(opts, :scope_columns))
      matchers(opts, :except)
    end

    opts
  end

  defp validate_boolean_option!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_boolean(value) ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "expected scoped_foreign_keys #{inspect(key)} to be a boolean, got: #{inspect(value)}"

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

  defp scope_columns!(values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_scope_columns_error!()
    end

    values
  end

  defp scope_columns!(_values), do: raise_scope_columns_error!()

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_filter_error!(key) do
    raise ArgumentError,
          "expected scoped_foreign_keys #{inspect(key)} to be a non-empty list of strings"
  end

  defp raise_scope_columns_error! do
    raise ArgumentError,
          "expected scoped_foreign_keys :scope_columns to be a non-empty list of strings"
  end

  defp matchers(opts, key) do
    case Keyword.get(opts, key, []) do
      [] -> []
      value when is_list(value) -> matchers!(key, value)
      _value -> raise_matcher_error!(key)
    end
  end

  defp matchers!(key, value) do
    cond do
      Keyword.keyword?(value) ->
        [matcher!(key, value)]

      Enum.all?(value, &Keyword.keyword?/1) ->
        Enum.map(value, &matcher!(key, &1))

      true ->
        raise_matcher_error!(key)
    end
  end

  defp matcher!(key, matcher) do
    allowed_keys = [
      :schema,
      :schemas,
      :table,
      :tables,
      :constraint,
      :constraints,
      :referenced_table,
      :referenced_tables
    ]

    Enum.each(matcher, fn {matcher_key, matcher_value} ->
      if matcher_key not in allowed_keys do
        raise ArgumentError,
              "unknown scoped_foreign_keys #{inspect(key)} matcher option: #{inspect(matcher_key)}"
      end

      matcher_values!(key, matcher_key, matcher_value)
    end)

    if Enum.empty?(matcher) do
      raise_matcher_error!(key)
    end

    matcher
  end

  defp matcher_values!(key, matcher_key, values)
       when matcher_key in [:schemas, :tables, :constraints, :referenced_tables] do
    if not is_list(values) or Enum.empty?(values) or Enum.any?(values, &(not matcher_value?(&1))) do
      raise_matcher_values_error!(key, matcher_key)
    end
  end

  defp matcher_values!(key, matcher_key, value) do
    if not matcher_value?(value) do
      raise_matcher_values_error!(key, matcher_key)
    end
  end

  defp matcher_value?(%Regex{}), do: true
  defp matcher_value?(value), do: non_empty_string?(value)

  defp raise_matcher_error!(key) do
    raise ArgumentError,
          "expected scoped_foreign_keys #{inspect(key)} to be a matcher or non-empty list of matchers"
  end

  defp raise_matcher_values_error!(key, matcher_key) do
    raise ArgumentError,
          "expected scoped_foreign_keys #{inspect(key)} #{inspect(matcher_key)} to be a matcher value or non-empty list of matcher values"
  end

  defp matches_any?(_row, []), do: false
  defp matches_any?(row, matchers), do: Enum.any?(matchers, &matches?(row, &1))

  defp matches?(row, matcher) do
    Enum.all?(matcher, fn
      {:schema, values} -> matches_value?(value(row, "schema_name"), values)
      {:schemas, values} -> matches_value?(value(row, "schema_name"), values)
      {:table, values} -> matches_value?(value(row, "table_name"), values)
      {:tables, values} -> matches_value?(value(row, "table_name"), values)
      {:constraint, values} -> matches_value?(value(row, "constraint_name"), values)
      {:constraints, values} -> matches_value?(value(row, "constraint_name"), values)
      {:referenced_table, values} -> matches_value?(value(row, "referenced_table_name"), values)
      {:referenced_tables, values} -> matches_value?(value(row, "referenced_table_name"), values)
    end)
  end

  defp matches_value?(value, values) when is_list(values),
    do: Enum.any?(values, &matches_value?(value, &1))

  defp matches_value?(value, %Regex{} = regex), do: Regex.match?(regex, value)
  defp matches_value?(value, expected), do: value == expected

  @spec issue(target :: Target.t(), row :: result_row(), scope_columns :: list(String.t())) ::
          Issue.t()
  defp issue(target, row, scope_columns) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    constraint_name = value(row, "constraint_name")
    column_names = value(row, "column_names")
    referenced_schema_name = value(row, "referenced_schema_name")
    referenced_table_name = value(row, "referenced_table_name")
    referenced_column_names = value(row, "referenced_column_names")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected foreign key #{constraint_name} on #{schema_name}.#{table_name} " <>
          "to include required scope columns #{Enum.join(scope_columns, ", ")}",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        constraint: constraint_name,
        columns: column_names,
        referenced_schema: referenced_schema_name,
        referenced_table: referenced_table_name,
        referenced_columns: referenced_column_names,
        scope_columns: scope_columns
      }
    }
  end

  @spec query_error_issue(
          target :: Target.t(),
          schemas :: list(String.t()) | nil,
          tables :: list(String.t()) | nil,
          scope_columns :: list(String.t()),
          exceptions :: list(matcher()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, schemas, tables, scope_columns, exceptions, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres scoped foreign keys",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schemas: schemas,
        tables: tables,
        scope_columns: scope_columns,
        except: exceptions,
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
