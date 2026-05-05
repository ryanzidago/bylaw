defmodule Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns do
  @moduledoc """
  Validates that Postgres tables include required columns.

  Pass `columns: [...]` with the column names every table in scope must have.
  By default the check inspects all non-system schemas in a Postgres target.
  Pass `:schemas` or `:tables` options to narrow the scope.

  Use `except_tables: [...]` to skip table names in every schema, or
  `except_table_refs: [{"schema", "table"}]` to skip specific schema-qualified
  tables.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @query """
  WITH scoped_tables AS (
    SELECT
      namespace.nspname AS schema_name,
      table_class.relname AS table_name,
      table_class.oid AS table_oid
    FROM pg_catalog.pg_class AS table_class
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = table_class.relnamespace
    WHERE table_class.relkind IN ('r', 'p')
      AND namespace.nspname <> 'information_schema'
      AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
      AND ($2::text[] IS NULL OR namespace.nspname = ANY($2))
      AND ($3::text[] IS NULL OR table_class.relname = ANY($3))
      AND ($4::text[] IS NULL OR table_class.relname <> ALL($4))
      AND (
        $5::text[] IS NULL
        OR NOT EXISTS (
          SELECT 1
          FROM unnest($5::text[], $6::text[]) AS except_table(schema_name, table_name)
          WHERE except_table.schema_name = namespace.nspname
            AND except_table.table_name = table_class.relname
        )
      )
  )
  SELECT
    scoped_tables.schema_name,
    scoped_tables.table_name,
    ARRAY_AGG(required_column.column_name ORDER BY required_column.column_name) AS missing_columns
  FROM scoped_tables
  CROSS JOIN unnest($1::text[]) AS required_column(column_name)
  LEFT JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = scoped_tables.table_oid
   AND attribute.attname = required_column.column_name
   AND attribute.attnum > 0
   AND NOT attribute.attisdropped
  WHERE attribute.attnum IS NULL
  GROUP BY scoped_tables.schema_name, scoped_tables.table_name
  ORDER BY scoped_tables.schema_name, scoped_tables.table_name
  """

  @type table_ref :: {String.t(), String.t()}

  @type check_opt ::
          {:validate, boolean()}
          | {:columns, list(String.t())}
          | {:schemas, list(String.t())}
          | {:tables, list(String.t())}
          | {:except_tables, list(String.t())}
          | {:except_table_refs, list(table_ref())}

  @type check_opts :: list(check_opt())

  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "missing_columns" => :missing_columns,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Returns the option namespace used by this check.
  """
  @impl Bylaw.Db.Check
  @spec name() :: :required_columns
  def name, do: :required_columns

  @doc """
  Validates that tables in scope include the required columns.

  The check is enabled by default. Pass `validate: false` to skip it.
  `columns: [...]` is required when validation is enabled.
  """
  @impl Bylaw.Db.Check
  @spec validate(Target.t(), check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_required_columns(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected required_columns opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_required_columns(target, opts) do
    columns = required_filter!(opts, :columns)
    schemas = filter(opts, :schemas)
    tables = filter(opts, :tables)
    except_tables = filter(opts, :except_tables)
    {except_schemas, except_table_names} = except_table_ref_filters(opts)

    case Postgres.query(
           target,
           @query,
           [columns, schemas, tables, except_tables, except_schemas, except_table_names],
           []
         ) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.map(&issue(target, &1))
        |> result()

      {:error, reason} ->
        {:error,
         [
           query_error_issue(
             target,
             columns,
             schemas,
             tables,
             except_tables,
             except_table_refs(opts),
             reason
           )
         ]}
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
            "expected required_columns opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [
      :validate,
      :columns,
      :schemas,
      :tables,
      :except_tables,
      :except_table_refs
    ]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown required_columns option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)
    validate_filter_option!(opts, :columns)
    validate_filter_option!(opts, :schemas)
    validate_filter_option!(opts, :tables)
    validate_filter_option!(opts, :except_tables)
    validate_except_table_refs!(opts)

    opts
  end

  defp validate_boolean_option!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_boolean(value) ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "expected required_columns #{inspect(key)} to be a boolean, got: #{inspect(value)}"

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

  defp validate_except_table_refs!(opts) do
    case Keyword.fetch(opts, :except_table_refs) do
      {:ok, values} ->
        except_table_refs!(values)
        :ok

      :error ->
        :ok
    end
  end

  defp required_filter!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, values} -> filter!(key, values)
      :error -> raise_filter_error!(key)
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

  defp except_table_ref_filters(opts) do
    refs = except_table_refs(opts)

    if Enum.empty?(refs) do
      {nil, nil}
    else
      Enum.unzip(refs)
    end
  end

  defp except_table_refs(opts) do
    opts
    |> Keyword.get(:except_table_refs, [])
    |> except_table_refs!()
  end

  defp except_table_refs!(values) when is_list(values) do
    if Enum.any?(values, &(not table_ref?(&1))) do
      raise_except_table_refs_error!()
    end

    values
  end

  defp except_table_refs!(_values), do: raise_except_table_refs_error!()

  defp table_ref?({schema_name, table_name}) do
    non_empty_string?(schema_name) and non_empty_string?(table_name)
  end

  defp table_ref?(_value), do: false

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_filter_error!(key) do
    raise ArgumentError,
          "expected required_columns #{inspect(key)} to be a non-empty list of strings"
  end

  defp raise_except_table_refs_error! do
    raise ArgumentError,
          "expected required_columns :except_table_refs to be a list of {schema, table} string tuples"
  end

  @spec issue(Target.t(), result_row()) :: Issue.t()
  defp issue(target, row) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    missing_columns = value(row, "missing_columns")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected #{schema_name}.#{table_name} to include required columns #{Enum.join(missing_columns, ", ")}",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        missing_columns: missing_columns
      }
    }
  end

  @spec query_error_issue(
          Target.t(),
          list(String.t()),
          list(String.t()) | nil,
          list(String.t()) | nil,
          list(String.t()) | nil,
          list(table_ref()),
          term()
        ) :: Issue.t()
  defp query_error_issue(
         target,
         columns,
         schemas,
         tables,
         except_tables,
         except_table_refs,
         reason
       ) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres table columns",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        columns: columns,
        schemas: schemas,
        tables: tables,
        except_tables: except_tables,
        except_table_refs: except_table_refs,
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
