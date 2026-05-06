defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability do
  @moduledoc """
  Validates that Postgres foreign key columns are not nullable.

  By default the check inspects all non-system schemas in a Postgres target. Use
  `rules: [[only: ...]]` to narrow the scope or exclude intentionally optional
  foreign keys:

      {ForeignKeyNullability,
       rules: [
         [
           only: [schema: "public"],
           except: [
             [table: "runs", column: "assistant_message_id"],
             [constraint: "messages_parent_message_id_fkey"]
           ]
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
  SELECT
    namespace.nspname AS schema_name,
    table_class.relname AS table_name,
    constraint_record.conname AS constraint_name,
    attribute.attname AS column_name
  FROM pg_catalog.pg_constraint AS constraint_record
  JOIN pg_catalog.pg_class AS table_class
    ON table_class.oid = constraint_record.conrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = table_class.relnamespace
  JOIN unnest(constraint_record.conkey) AS key(attnum)
    ON true
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = constraint_record.conrelid
   AND attribute.attnum = key.attnum
  WHERE constraint_record.contype = 'f'
    AND NOT attribute.attnotnull
    AND namespace.nspname <> 'information_schema'
    AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
    AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
    AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
  ORDER BY schema_name, table_name, constraint_name, column_name
  """

  @type matcher_value :: String.t() | Regex.t()
  @type matcher_values :: matcher_value() | list(matcher_value())
  @type matcher ::
          list(
            {:schema, matcher_values()}
            | {:table, matcher_values()}
            | {:constraint, matcher_values()}
            | {:column, matcher_values()}
          )
  @type rule ::
          list({:only, matcher() | list(matcher())} | {:except, matcher() | list(matcher())})
  @type check_opt :: {:validate, boolean()} | {:rules, list(rule())}

  @type check_opts :: list(check_opt())

  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "column_name" => :column_name,
    "constraint_name" => :constraint_name,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Validates that foreign key columns in the target scope are `NOT NULL`.

  The check is enabled by default. Pass `validate: false` to skip it. Use
  `rules: [[only: [schema: "public"]]]` to narrow the default all-schema scope.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if RuleOptions.enabled?(opts) do
      validate_foreign_key_nullability(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected foreign_key_nullability opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_foreign_key_nullability(target, opts) do
    rules = RuleOptions.default_rules!(opts, :foreign_key_nullability, allowed_matcher_keys())
    schemas = RuleOptions.filter(opts, :schemas, :foreign_key_nullability)
    tables = RuleOptions.filter(opts, :tables, :foreign_key_nullability)

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
    RuleOptions.keyword_list!(opts, :foreign_key_nullability)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :schemas, :tables, :except],
      :foreign_key_nullability
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :foreign_key_nullability)

    if RuleOptions.enabled?(opts) do
      RuleOptions.default_rules!(opts, :foreign_key_nullability, allowed_matcher_keys())
      RuleOptions.filter(opts, :schemas, :foreign_key_nullability)
      RuleOptions.filter(opts, :tables, :foreign_key_nullability)
    end

    opts
  end

  defp matches_rules?(row, rules),
    do: Enum.any?(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)

  defp matcher_value(row, :schema), do: value(row, "schema_name")
  defp matcher_value(row, :table), do: value(row, "table_name")
  defp matcher_value(row, :constraint), do: value(row, "constraint_name")
  defp matcher_value(row, :column), do: value(row, "column_name")

  defp allowed_matcher_keys, do: [:schema, :table, :constraint, :column]

  @spec issue(target :: Target.t(), row :: result_row()) :: Issue.t()
  defp issue(target, row) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    constraint_name = value(row, "constraint_name")
    column_name = value(row, "column_name")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected foreign key #{constraint_name} on #{schema_name}.#{table_name}.#{column_name} to be NOT NULL",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        constraint: constraint_name,
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
      message: "could not inspect Postgres foreign key nullability",
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
