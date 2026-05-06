defmodule Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType do
  @moduledoc """
  Validates that Postgres primary key columns use configured data types.

  By default the check inspects all non-system schemas in a Postgres target. Use
  `rules: [...]` to configure allowed types for scoped groups of tables:

      {PrimaryKeyType,
       rules: [
         [
           only: [schema: "public"],
           types: ["uuid"],
           except: [[table: "schema_migrations"]]
         ]
       ]}
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.RuleOptions
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
            | {:table, matcher_values()}
            | {:column, matcher_values()}
          )
  @type rule ::
          list(
            {:only, matcher() | list(matcher())}
            | {:except, matcher() | list(matcher())}
            | {:types, list(String.t())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:rules, list(rule())}

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
  Validates that every table in scope has a primary key using allowed types.

  The check is enabled by default. Pass `validate: false` to skip it. Validation
  requires `rules: [[types: [...]]]`, such as
  `rules: [[types: ["uuid"]]]`.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if RuleOptions.enabled?(opts) do
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
    rules = normalize_rules!(opts)
    schemas = RuleOptions.filter(opts, :schemas, :primary_key_type)
    tables = RuleOptions.filter(opts, :tables, :primary_key_type)

    case Postgres.query(target, @query, [schemas, tables, query_types(rules, opts)], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.filter(&(matches_rules?(&1, rules) and violates_matching_rule?(&1, rules)))
        |> Enum.map(&issue(target, &1, matching_types(&1, rules)))
        |> result()

      {:error, reason} ->
        {:error, [query_error_issue(target, rules, reason)]}
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
    RuleOptions.keyword_list!(opts, :primary_key_type)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :types, :schemas, :tables, :except],
      :primary_key_type
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :primary_key_type)

    if RuleOptions.enabled?(opts) do
      normalize_rules!(opts)
      RuleOptions.filter(opts, :schemas, :primary_key_type)
      RuleOptions.filter(opts, :tables, :primary_key_type)
    end

    opts
  end

  defp normalize_rules!(opts) do
    cond do
      Keyword.has_key?(opts, :rules) ->
        opts
        |> Keyword.fetch!(:rules)
        |> RuleOptions.rules!(
          :primary_key_type,
          allowed_matcher_keys(),
          [:types],
          &rule_payload!/1
        )

      Keyword.has_key?(opts, :types) ->
        [
          %{
            types: types!(Keyword.fetch!(opts, :types)),
            only: legacy_only(opts),
            except: RuleOptions.matchers(opts, :except, :primary_key_type, allowed_matcher_keys())
          }
        ]

      true ->
        raise ArgumentError, "expected primary_key_type to include :types"
    end
  end

  defp legacy_only(opts) do
    matcher =
      []
      |> maybe_put_matcher(:schema, Keyword.get(opts, :schemas))
      |> maybe_put_matcher(:table, Keyword.get(opts, :tables))

    if Enum.empty?(matcher), do: [], else: [matcher]
  end

  defp maybe_put_matcher(matcher, _key, nil), do: matcher
  defp maybe_put_matcher(matcher, key, value), do: Keyword.put(matcher, key, value)

  defp query_types(_rules, opts) do
    if Keyword.has_key?(opts, :types), do: Keyword.fetch!(opts, :types), else: []
  end

  defp rule_payload!(rule) do
    if not Keyword.has_key?(rule, :types) do
      raise ArgumentError, "expected primary_key_type rule to include :types"
    end

    %{types: types!(Keyword.fetch!(rule, :types))}
  end

  defp types!(values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_types_error!()
    end

    values
  end

  defp types!(_values), do: raise_types_error!()

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_types_error! do
    raise ArgumentError, "expected primary_key_type :types to be a non-empty list of strings"
  end

  defp matches_rules?(row, rules),
    do: Enum.any?(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)

  defp matching_types(row, rules) do
    rules
    |> Enum.filter(fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)
    |> Enum.flat_map(& &1.types)
    |> Enum.uniq()
  end

  defp violates_matching_rule?(row, rules) do
    case value(row, "reason") do
      reason when reason in ["missing_primary_key", :missing_primary_key] ->
        true

      reason when reason in ["wrong_type", :wrong_type] ->
        value(row, "actual_type") not in matching_types(row, rules)
    end
  end

  defp matcher_value(row, :schema), do: value(row, "schema_name")
  defp matcher_value(row, :table), do: value(row, "table_name")
  defp matcher_value(row, :column), do: value(row, "column_name")

  defp allowed_matcher_keys, do: [:schema, :table, :column]

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
          rules :: list(map()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, rules, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres primary key types",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        rules: rules,
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
