defmodule Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType do
  @moduledoc """
  Validates that Postgres primary key columns use configured data types.

  By default the check inspects all non-system schemas in a Postgres target.
  Pass `:schemas` or `:tables` options to narrow the scope. Use `:except` for
  intentional exceptions:

      {PrimaryKeyType,
       schemas: ["public"],
       types: ["uuid"],
       except: [[table: "schema_migrations"]]}
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
      AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
      AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
  ),
  primary_key_columns AS (
    SELECT
      scoped_tables.schema_name,
      scoped_tables.table_name,
      attribute.attname AS column_name,
      pg_catalog.format_type(attribute.atttypid, attribute.atttypmod) AS actual_type
    FROM scoped_tables
    JOIN pg_catalog.pg_constraint AS constraint_record
      ON constraint_record.conrelid = scoped_tables.table_oid
     AND constraint_record.contype = 'p'
    JOIN unnest(constraint_record.conkey) WITH ORDINALITY AS key(attnum, position)
      ON true
    JOIN pg_catalog.pg_attribute AS attribute
      ON attribute.attrelid = scoped_tables.table_oid
     AND attribute.attnum = key.attnum
     AND attribute.attnum > 0
     AND NOT attribute.attisdropped
  )
  SELECT
    scoped_tables.schema_name,
    scoped_tables.table_name,
    NULL::text AS column_name,
    NULL::text AS actual_type,
    'missing_primary_key'::text AS reason
  FROM scoped_tables
  WHERE NOT EXISTS (
    SELECT 1
    FROM primary_key_columns
    WHERE primary_key_columns.schema_name = scoped_tables.schema_name
      AND primary_key_columns.table_name = scoped_tables.table_name
  )
  UNION ALL
  SELECT
    primary_key_columns.schema_name,
    primary_key_columns.table_name,
    primary_key_columns.column_name,
    primary_key_columns.actual_type,
    'wrong_type'::text AS reason
  FROM primary_key_columns
  WHERE primary_key_columns.actual_type <> ALL($3::text[])
  ORDER BY schema_name, table_name, column_name NULLS FIRST
  """

  @type matcher_value :: String.t() | Regex.t()
  @type matcher_values :: matcher_value() | list(matcher_value())
  @type matcher ::
          list(
            {:schema, matcher_values()}
            | {:schemas, list(matcher_value())}
            | {:table, matcher_values()}
            | {:tables, list(matcher_value())}
            | {:column, matcher_values()}
            | {:columns, list(matcher_value())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:types, list(String.t())}
          | {:schemas, list(String.t())}
          | {:tables, list(String.t())}
          | {:except, matcher() | list(matcher())}

  @type check_opts :: list(check_opt())

  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "actual_type" => :actual_type,
    "column_name" => :column_name,
    "reason" => :reason,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Returns the option namespace used by this check.
  """
  @impl Bylaw.Db.Check
  @spec name() :: :primary_key_type
  def name, do: :primary_key_type

  @doc """
  Validates that every table in scope has a primary key using allowed types.

  The check is enabled by default. Pass `validate: false` to skip it. Validation
  requires `types: [...]`, such as `types: ["uuid"]` or
  `types: ["uuid", "bigint"]`.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_primary_key_type(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected primary_key_type opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_primary_key_type(target, opts) do
    schemas = filter(opts, :schemas)
    tables = filter(opts, :tables)
    types = types!(Keyword.fetch!(opts, :types))
    exceptions = matchers(opts, :except)

    case Postgres.query(target, @query, [schemas, tables, types], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.reject(&matches_any?(&1, exceptions))
        |> Enum.map(&issue(target, &1, types))
        |> result()

      {:error, reason} ->
        {:error, [query_error_issue(target, schemas, tables, types, exceptions, reason)]}
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
            "expected primary_key_type opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :types, :schemas, :tables, :except]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown primary_key_type option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)
    validate_filter_option!(opts, :schemas)
    validate_filter_option!(opts, :tables)

    if Keyword.get(opts, :validate, true) == true do
      if not Keyword.has_key?(opts, :types) do
        raise ArgumentError, "expected primary_key_type to include :types"
      end

      types!(Keyword.fetch!(opts, :types))
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
              "expected primary_key_type #{inspect(key)} to be a boolean, got: #{inspect(value)}"

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

  defp types!(values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_types_error!()
    end

    values
  end

  defp types!(_values), do: raise_types_error!()

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_filter_error!(key) do
    raise ArgumentError,
          "expected primary_key_type #{inspect(key)} to be a non-empty list of strings"
  end

  defp raise_types_error! do
    raise ArgumentError, "expected primary_key_type :types to be a non-empty list of strings"
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

      Enum.empty?(value) ->
        raise_matcher_error!(key)

      Enum.all?(value, &Keyword.keyword?/1) ->
        Enum.map(value, &matcher!(key, &1))

      true ->
        raise_matcher_error!(key)
    end
  end

  defp matcher!(key, matcher) do
    allowed_keys = [:schema, :schemas, :table, :tables, :column, :columns]

    Enum.each(matcher, fn {matcher_key, matcher_value} ->
      if matcher_key not in allowed_keys do
        raise ArgumentError,
              "unknown primary_key_type #{inspect(key)} matcher option: #{inspect(matcher_key)}"
      end

      matcher_values!(key, matcher_key, matcher_value)
    end)

    if Enum.empty?(matcher) do
      raise_matcher_error!(key)
    end

    matcher
  end

  defp matcher_values!(key, matcher_key, values)
       when matcher_key in [:schemas, :tables, :columns] do
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
          "expected primary_key_type #{inspect(key)} to be a matcher or non-empty list of matchers"
  end

  defp raise_matcher_values_error!(key, matcher_key) do
    raise ArgumentError,
          "expected primary_key_type #{inspect(key)} #{inspect(matcher_key)} to be a matcher value or non-empty list of matcher values"
  end

  defp matches_any?(_row, []), do: false
  defp matches_any?(row, matchers), do: Enum.any?(matchers, &matches?(row, &1))

  defp matches?(row, matcher) do
    Enum.all?(matcher, fn
      {:schema, values} -> matches_value?(value(row, "schema_name"), values)
      {:schemas, values} -> matches_value?(value(row, "schema_name"), values)
      {:table, values} -> matches_value?(value(row, "table_name"), values)
      {:tables, values} -> matches_value?(value(row, "table_name"), values)
      {:column, values} -> matches_value?(value(row, "column_name"), values)
      {:columns, values} -> matches_value?(value(row, "column_name"), values)
    end)
  end

  defp matches_value?(value, values) when is_list(values),
    do: Enum.any?(values, &matches_value?(value, &1))

  defp matches_value?(nil, _expected), do: false
  defp matches_value?(value, %Regex{} = regex), do: Regex.match?(regex, value)
  defp matches_value?(value, expected), do: value == expected

  @spec issue(target :: Target.t(), row :: result_row(), types :: list(String.t())) :: Issue.t()
  defp issue(target, row, types) do
    case value(row, "reason") do
      "missing_primary_key" -> missing_primary_key_issue(target, row, types)
      :missing_primary_key -> missing_primary_key_issue(target, row, types)
      "wrong_type" -> wrong_type_issue(target, row, types)
      :wrong_type -> wrong_type_issue(target, row, types)
    end
  end

  defp missing_primary_key_issue(target, row, types) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")

    %Issue{
      check: __MODULE__,
      target: target,
      message: "expected #{schema_name}.#{table_name} to declare a primary key",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        types: types,
        actual_type: nil,
        reason: :missing_primary_key
      }
    }
  end

  defp wrong_type_issue(target, row, types) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    column_name = value(row, "column_name")
    actual_type = value(row, "actual_type")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected primary key #{schema_name}.#{table_name}.#{column_name} to use one of: #{Enum.join(types, ", ")}, got: #{actual_type}",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        column: column_name,
        types: types,
        actual_type: actual_type,
        reason: :wrong_type
      }
    }
  end

  @spec query_error_issue(
          target :: Target.t(),
          schemas :: list(String.t()) | nil,
          tables :: list(String.t()) | nil,
          types :: list(String.t()),
          exceptions :: list(matcher()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, schemas, tables, types, exceptions, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres primary key types",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schemas: schemas,
        tables: tables,
        types: types,
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
