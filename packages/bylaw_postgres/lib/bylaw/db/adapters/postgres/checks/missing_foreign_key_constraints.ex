defmodule Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints do
  @moduledoc """
  Flags Postgres columns that look like foreign keys but have no constraint.

  ## Examples

  Before, `account_id` looks like a relationship but the database does not
  enforce it:

  ```sql
  CREATE TABLE orders (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL
  );
  ```

  Application code can insert orphaned `orders.account_id` values, and bugs may
  only surface later as missing joins or cleanup problems.

  After, make the relationship explicit in Postgres:

  ```sql
  CREATE TABLE orders (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts(id)
  );
  ```

  The database now rejects orphaned rows no matter which code path writes to the
  table.

  ## Notes

  This check does not infer relationships from column names that do not end in
  `_id`, and it does not validate whether the referenced table name matches the
  column name. It only checks whether a candidate column is covered by a
  Postgres foreign key constraint.

  ## Options

    * `:validate` - explicit `false` disables this check.
    * `:rules` - optional rule keyword list or non-empty list of rule keyword
      lists. Rules use only shared scope keys.

  Run globally with defaults:

  ```elixir
  Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints
  ```

  Run only for matching rule scopes:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints,
   rules: [where: [schemas: ["public"]]]}

  {Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints,
   rules: [
     where: [schemas: ["public"]],
     except: [
       [tables: ["events"], columns: ["actor_id"]],
       [columns: [~r/_external_id$/]]
     ]
   ]}
  ```

  A column is treated as a candidate when it ends in `_id`, is not named `id`,
  is not part of a primary key, and is not covered by a declared foreign key
  constraint.

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

  @type check_opt :: {:validate, boolean()} | {:rules, keyword() | list(keyword())}

  @type check_opts :: list(check_opt())

  @row_keys %{
    "column_name" => :column_name,
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

    case Postgres.query(target, @query, [nil, nil], []) do
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
    RuleOptions.keyword_list!(opts, :missing_foreign_key_constraints)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules],
      :missing_foreign_key_constraints
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :missing_foreign_key_constraints)

    if RuleOptions.enabled?(opts) do
      RuleOptions.default_rules!(opts, :missing_foreign_key_constraints, allowed_matcher_keys())
    end

    opts
  end

  defp matches_rules?(row, rules),
    do: Enum.any?(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)

  defp matcher_value(row, :schema), do: Result.value(row, "schema_name", @row_keys)
  defp matcher_value(row, :table), do: Result.value(row, "table_name", @row_keys)
  defp matcher_value(row, :column), do: Result.value(row, "column_name", @row_keys)

  defp allowed_matcher_keys, do: [:schema, :table, :column]

  @spec issue(target :: Target.t(), row :: Result.row()) :: Issue.t()
  defp issue(target, row) do
    schema_name = Result.value(row, "schema_name", @row_keys)
    table_name = Result.value(row, "table_name", @row_keys)
    column_name = Result.value(row, "column_name", @row_keys)

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
end
