defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability do
  @moduledoc """
  Validates that Postgres foreign key columns are not nullable.

  ## Examples

  Before, the foreign key allows missing parents:

  ```sql
  CREATE TABLE orders (
    id uuid PRIMARY KEY,
    account_id uuid REFERENCES accounts(id)
  );
  ```

  That makes the association optional even if the application treats every order
  as belonging to an account. Code then has to handle impossible `NULL` cases.

  After, make the required relationship non-nullable:

  ```sql
  CREATE TABLE orders (
    id uuid PRIMARY KEY,
    account_id uuid NOT NULL REFERENCES accounts(id)
  );
  ```

  The database shape now matches the domain model, and callers can rely on the
  relationship being present.

  ## Notes

  This check only inspects columns that are already part of a foreign key
  constraint. Optional relationships should be excluded with an `except`
  matcher.

  ## Options

  By default the check inspects all non-system schemas in a Postgres target. Use
  `rules: [[where: ...]]` to narrow the scope or exclude intentionally optional
  foreign keys:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability,
   rules: [
     [
       where: [schemas: ["public"]],
       except: [
         [tables: ["runs"], columns: ["assistant_message_id"]],
         [constraints: ["messages_parent_message_id_fkey"]]
       ]
     ]
   ]}
  ```

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
  @type matcher_values :: list(matcher_value())
  @type matcher ::
          list(
            {:schema, matcher_values()}
            | {:table, matcher_values()}
            | {:constraint, matcher_values()}
            | {:column, matcher_values()}
          )
  @type rule ::
          list({:where, matcher() | list(matcher())} | {:except, matcher() | list(matcher())})
  @type check_opt :: {:validate, boolean()} | {:rules, list(rule())}

  @type check_opts :: list(check_opt())

  @row_keys %{
    "column_name" => :column_name,
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
        |> Result.rows()
        |> Enum.filter(&matches_rules?(&1, rules))
        |> Enum.map(&issue(target, &1))
        |> Result.to_check_result()

      {:error, reason} ->
        {:error, [query_error_issue(target, rules, reason)]}
    end
  end

  defp check_opts!(opts) do
    RuleOptions.keyword_list!(opts, :foreign_key_nullability)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :schemas, :tables, :except],
      :foreign_key_nullability
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :foreign_key_nullability)

    if RuleOptions.enabled?(opts) do
      RuleOptions.reject_top_level_keys_with_rules!(
        opts,
        [:schemas, :tables, :except],
        :foreign_key_nullability
      )

      RuleOptions.default_rules!(opts, :foreign_key_nullability, allowed_matcher_keys())
      RuleOptions.filter(opts, :schemas, :foreign_key_nullability)
      RuleOptions.filter(opts, :tables, :foreign_key_nullability)
    end

    opts
  end

  defp matches_rules?(row, rules),
    do: Enum.any?(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)

  defp matcher_value(row, :schema), do: Result.value(row, "schema_name", @row_keys)
  defp matcher_value(row, :table), do: Result.value(row, "table_name", @row_keys)
  defp matcher_value(row, :constraint), do: Result.value(row, "constraint_name", @row_keys)
  defp matcher_value(row, :column), do: Result.value(row, "column_name", @row_keys)

  defp allowed_matcher_keys, do: [:schema, :table, :constraint, :column]

  @spec issue(target :: Target.t(), row :: Result.row()) :: Issue.t()
  defp issue(target, row) do
    schema_name = Result.value(row, "schema_name", @row_keys)
    table_name = Result.value(row, "table_name", @row_keys)
    constraint_name = Result.value(row, "constraint_name", @row_keys)
    column_name = Result.value(row, "column_name", @row_keys)

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
end
