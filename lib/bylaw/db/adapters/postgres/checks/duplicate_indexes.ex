defmodule Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes do
  @moduledoc """
  Flags equivalent Postgres indexes on the same table.

  By default the check inspects all non-system schemas in a Postgres target. Use
  `rules: [[only: ...]]` to narrow the scope. Indexes are treated as duplicates
  when they have the same table, access method, uniqueness,
  validity, key and included columns, operator classes, collations, sort options,
  expressions, and predicate.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.RuleOptions
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

  @type check_opt ::
          {:validate, boolean()}
          | {:rules, list(keyword())}

  @type check_opts :: list(check_opt())

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
  Validates that tables do not have duplicate indexes.

  The check is enabled by default. Pass `validate: false` to skip it. Use
  `rules: [[only: [schema: "public"]]]` to narrow the default all-schema scope.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if RuleOptions.enabled?(opts) do
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
    rules = RuleOptions.default_rules!(opts, :duplicate_indexes, allowed_matcher_keys())
    schemas = RuleOptions.filter(opts, :schemas, :duplicate_indexes)
    tables = RuleOptions.filter(opts, :tables, :duplicate_indexes)

    case Postgres.query(target, @query, [schemas, tables], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.filter(&matches_rules?(&1, rules))
        |> Enum.map(&issue(target, &1))
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
    RuleOptions.keyword_list!(opts, :duplicate_indexes)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :schemas, :tables],
      :duplicate_indexes
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :duplicate_indexes)

    if RuleOptions.enabled?(opts) do
      RuleOptions.reject_top_level_keys_with_rules!(opts, [:schemas, :tables], :duplicate_indexes)
      RuleOptions.default_rules!(opts, :duplicate_indexes, allowed_matcher_keys())
      RuleOptions.filter(opts, :schemas, :duplicate_indexes)
      RuleOptions.filter(opts, :tables, :duplicate_indexes)
    end

    opts
  end

  defp matches_rules?(row, rules),
    do: Enum.any?(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)

  defp matcher_value(row, :schema), do: value(row, "schema_name")
  defp matcher_value(row, :table), do: value(row, "table_name")

  defp allowed_matcher_keys, do: [:schema, :table]

  @spec issue(target :: Target.t(), row :: result_row()) :: Issue.t()
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

  @spec query_error_issue(
          target :: Target.t(),
          rules :: list(RuleOptions.rule()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, rules, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres indexes",
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
