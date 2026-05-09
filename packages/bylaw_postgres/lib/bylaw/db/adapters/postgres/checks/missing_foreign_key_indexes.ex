defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes do
  @moduledoc """
  Validates that Postgres foreign keys have supporting indexes.

  ## Examples

  Before, the foreign key exists but the referencing column has no index:

  ```sql
  CREATE TABLE accounts (
    id uuid PRIMARY KEY
  );

  CREATE TABLE orders (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts(id)
  );
  ```

  Deletes or primary-key updates on `accounts` can become slow because Postgres
  must scan `orders` to enforce the foreign key.

  After, add an index whose leading columns are the foreign key columns:

  ```sql
  CREATE INDEX orders_account_id_index ON orders (account_id);
  ```

  Postgres can enforce the relationship with an index lookup instead of a table
  scan.

  ## Notes

  The supporting index does not have to be unique, and it may include extra
  trailing columns such as `(account_id, inserted_at)`. Partial indexes such as
  `WHERE deleted_at IS NULL` do not count as support for the foreign key.

  ## Options

  By default the check inspects all non-system schemas in a Postgres target.
  Use `schemas: [...]` or `tables: [...]` for simple filtering:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
   schemas: ["public"],
   tables: ["orders", "line_items"]}
  ```

  Use `rules: [...]` when the scope needs matchers or exclusions:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
   rules: [
     [
       only: [schema: "public"],
       except: [[table: "audit_events"]]
     ]
   ]}
  ```

  A foreign key passes when the referencing table has a valid, non-partial index
  whose leading columns contain the foreign key columns.

  ## Usage

  Add this module to the checks passed to
  `Bylaw.Db.Adapters.Postgres.validate/2`. See the
  [README usage section](readme.html#usage) for the full ExUnit setup.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Result
  alias Bylaw.Db.Adapters.Postgres.RuleOptions
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
      AND namespace.nspname <> 'information_schema'
      AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
      AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
      AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
  ) AS foreign_key
  WHERE NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_index AS index_record
    WHERE index_record.indrelid = foreign_key.table_oid
      AND index_record.indisvalid
      AND index_record.indpred IS NULL
      AND index_record.indnkeyatts >= array_length(foreign_key.key_attnums, 1)
      AND foreign_key.key_attnums <@
        index_record.indkey[0:array_length(foreign_key.key_attnums, 1) - 1]
  )
  ORDER BY schema_name, table_name, constraint_name

  """

  @type check_opt ::
          {:validate, boolean()}
          | {:rules, list(keyword())}

  @type check_opts :: list(check_opt())

  @row_keys %{
    "column_names" => :column_names,
    "constraint_name" => :constraint_name,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Implements the `Bylaw.Db.Check` validation callback.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if RuleOptions.enabled?(opts) do
      validate_missing_foreign_key_indexes(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected missing_foreign_key_indexes opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_missing_foreign_key_indexes(target, opts) do
    rules = RuleOptions.default_rules!(opts, :missing_foreign_key_indexes, allowed_matcher_keys())
    schemas = RuleOptions.filter(opts, :schemas, :missing_foreign_key_indexes)
    tables = RuleOptions.filter(opts, :tables, :missing_foreign_key_indexes)

    case Postgres.query(target, @query, [schemas, tables], []) do
      {:ok, result} ->
        result
        |> Result.rows()
        |> Enum.filter(&matches_rules?(&1, rules))
        |> Enum.map(&issue(target, &1))
        |> Result.to_check_result()

      {:error, reason} ->
        {:error, [query_error_issue(target, rules, reason)]}
    end
  end

  defp check_opts!(opts) do
    RuleOptions.keyword_list!(opts, :missing_foreign_key_indexes)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :schemas, :tables],
      :missing_foreign_key_indexes
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :missing_foreign_key_indexes)

    if RuleOptions.enabled?(opts) do
      RuleOptions.reject_top_level_keys_with_rules!(
        opts,
        [:schemas, :tables],
        :missing_foreign_key_indexes
      )

      RuleOptions.default_rules!(opts, :missing_foreign_key_indexes, allowed_matcher_keys())
      RuleOptions.filter(opts, :schemas, :missing_foreign_key_indexes)
      RuleOptions.filter(opts, :tables, :missing_foreign_key_indexes)
    end

    opts
  end

  defp matches_rules?(row, rules),
    do: Enum.any?(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)

  defp matcher_value(row, :schema), do: Result.value(row, "schema_name", @row_keys)
  defp matcher_value(row, :table), do: Result.value(row, "table_name", @row_keys)

  defp allowed_matcher_keys, do: [:schema, :table]

  @spec issue(target :: Target.t(), row :: Result.row()) :: Issue.t()
  defp issue(target, row) do
    schema_name = Result.value(row, "schema_name", @row_keys)
    table_name = Result.value(row, "table_name", @row_keys)
    constraint_name = Result.value(row, "constraint_name", @row_keys)
    column_names = Result.value(row, "column_names", @row_keys)

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected foreign key #{constraint_name} on #{schema_name}.#{table_name} to have a supporting index",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        constraint: constraint_name,
        columns: column_names
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
      message: "could not inspect Postgres foreign keys",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        rules: rules,
        reason: reason
      }
    }
  end
end
