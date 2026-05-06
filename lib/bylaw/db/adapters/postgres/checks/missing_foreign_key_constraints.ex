defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints do
  @moduledoc """
  Flags Postgres columns that look like foreign keys but have no constraint.

  By default the check inspects all non-system schemas in a Postgres target. Use
  `rules: [[only: ...]]` to narrow the scope. A column is treated
  as a candidate when it ends in `_id`, is not named `id`, is not part of a
  primary key, and is not covered by a declared foreign key constraint.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.RuleOptions
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

  @type check_opt :: {:validate, boolean()} | {:rules, list(keyword())}

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
  `rules: [[only: [schema: "public"]]]` to narrow the default all-schema scope.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if RuleOptions.enabled?(opts) do
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
    rules =
      RuleOptions.default_rules!(opts, :missing_foreign_key_constraints, allowed_matcher_keys())

    schemas = RuleOptions.filter(opts, :schemas, :missing_foreign_key_constraints)
    tables = RuleOptions.filter(opts, :tables, :missing_foreign_key_constraints)

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
    RuleOptions.keyword_list!(opts, :missing_foreign_key_constraints)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :schemas, :tables],
      :missing_foreign_key_constraints
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :missing_foreign_key_constraints)

    if RuleOptions.enabled?(opts) do
      RuleOptions.default_rules!(opts, :missing_foreign_key_constraints, allowed_matcher_keys())
      RuleOptions.filter(opts, :schemas, :missing_foreign_key_constraints)
      RuleOptions.filter(opts, :tables, :missing_foreign_key_constraints)
    end

    opts
  end

  defp matches_rules?(row, rules),
    do: Enum.any?(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)

  defp matcher_value(row, :schema), do: value(row, "schema_name")
  defp matcher_value(row, :table), do: value(row, "table_name")
  defp matcher_value(row, :column), do: value(row, "column_name")

  defp allowed_matcher_keys, do: [:schema, :table, :column]

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
          rules :: list(RuleOptions.rule()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, rules, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres foreign key candidate columns",
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
