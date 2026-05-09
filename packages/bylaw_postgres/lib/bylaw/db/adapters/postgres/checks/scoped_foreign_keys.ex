defmodule Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeys do
  @moduledoc """
  Validates that scoped Postgres foreign keys include configured scope columns.

  ## Examples

  Before, both tables are tenant-scoped, but the foreign key only references
  `conversations(id)`:

  ```sql
  CREATE TABLE conversations (
    tenant_id uuid NOT NULL,
    id uuid NOT NULL,
    PRIMARY KEY (tenant_id, id),
    UNIQUE (id)
  );

  CREATE TABLE messages (
    tenant_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
  );
  ```

  A message can point at a conversation with the same `id` in another tenant if
  application code passes the wrong identifier.

  After, include the scope columns in the foreign key:

  ```sql
  CREATE TABLE messages (
    tenant_id uuid NOT NULL,
    conversation_id uuid NOT NULL,
    FOREIGN KEY (tenant_id, conversation_id)
      REFERENCES conversations(tenant_id, id)
  );
  ```

  Postgres now enforces that the child and parent rows belong to the same
  tenant, instead of relying on every query and write path to remember it.

  ## Notes

  The check only applies when the child table and referenced table both have
  every configured `scope_columns` column. Shared lookup tables that
  intentionally have no tenant column are not flagged unless they match a
  different rule.

  ## Options

  A foreign key is checked when both the child table and referenced table have
  every configured `:scope_columns` column. The foreign key must include those
  columns on both sides so a child row cannot point at a parent row from another
  scope:

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeys,
   rules: [
     [
       scope_columns: ["tenant_id", "workspace_id"],
       except: [[referenced_table: "global_settings"]]
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
            | {:table, matcher_values()}
            | {:constraint, matcher_values()}
            | {:referenced_table, matcher_values()}
          )
  @type rule ::
          list(
            {:only, matcher() | list(matcher())}
            | {:except, matcher() | list(matcher())}
            | {:scope_columns, list(String.t())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:rules, list(rule())}

  @type check_opts :: list(check_opt())

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
  Implements the `Bylaw.Db.Check` validation callback.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if RuleOptions.enabled?(opts) do
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
    opts
    |> normalize_rules!()
    |> Enum.flat_map(&rule_issues(target, &1))
    |> Result.to_check_result()
  end

  defp rule_issues(target, rule) do
    {schemas, tables} = query_filters(rule)

    case Postgres.query(target, @query, [schemas, tables, rule.scope_columns], []) do
      {:ok, result} ->
        result
        |> Result.rows()
        |> Enum.filter(fn row -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)
        |> Enum.map(&issue(target, &1, rule.scope_columns))

      {:error, reason} ->
        [query_error_issue(target, rule, reason)]
    end
  end

  defp check_opts!(opts) do
    RuleOptions.keyword_list!(opts, :scoped_foreign_keys)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :scope_columns],
      :scoped_foreign_keys
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :scoped_foreign_keys)

    if RuleOptions.enabled?(opts) do
      RuleOptions.reject_top_level_keys_with_rules!(opts, [:scope_columns], :scoped_foreign_keys)
      normalize_rules!(opts)
    end

    opts
  end

  defp normalize_rules!(opts) do
    cond do
      Keyword.has_key?(opts, :rules) ->
        opts
        |> Keyword.fetch!(:rules)
        |> RuleOptions.rules!(
          :scoped_foreign_keys,
          allowed_matcher_keys(),
          [:scope_columns],
          &rule_payload!/1
        )

      Keyword.has_key?(opts, :scope_columns) ->
        [
          %{
            scope_columns: scope_columns!(Keyword.fetch!(opts, :scope_columns)),
            only: [],
            except: []
          }
        ]

      true ->
        raise ArgumentError, "expected scoped_foreign_keys to include :scope_columns"
    end
  end

  defp rule_payload!(rule) do
    if not Keyword.has_key?(rule, :scope_columns) do
      raise ArgumentError, "expected scoped_foreign_keys rule to include :scope_columns"
    end

    %{scope_columns: scope_columns!(Keyword.fetch!(rule, :scope_columns))}
  end

  defp scope_columns!(values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_scope_columns_error!()
    end

    values
  end

  defp scope_columns!(_values), do: raise_scope_columns_error!()

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_scope_columns_error! do
    raise ArgumentError,
          "expected scoped_foreign_keys :scope_columns to be a non-empty list of strings"
  end

  defp matcher_value(row, :schema), do: Result.value(row, "schema_name", @row_keys)
  defp matcher_value(row, :table), do: Result.value(row, "table_name", @row_keys)
  defp matcher_value(row, :constraint), do: Result.value(row, "constraint_name", @row_keys)

  defp matcher_value(row, :referenced_table),
    do: Result.value(row, "referenced_table_name", @row_keys)

  defp allowed_matcher_keys, do: [:schema, :table, :constraint, :referenced_table]

  defp query_filters(%{only: [[schema: schemas, table: tables]]}),
    do: {List.wrap(schemas), List.wrap(tables)}

  defp query_filters(%{only: [[table: tables, schema: schemas]]}),
    do: {List.wrap(schemas), List.wrap(tables)}

  defp query_filters(%{only: [[schema: schemas]]}), do: {List.wrap(schemas), nil}
  defp query_filters(%{only: [[table: tables]]}), do: {nil, List.wrap(tables)}
  defp query_filters(_rule), do: {nil, nil}

  @spec issue(target :: Target.t(), row :: Result.row(), scope_columns :: list(String.t())) ::
          Issue.t()
  defp issue(target, row, scope_columns) do
    schema_name = Result.value(row, "schema_name", @row_keys)
    table_name = Result.value(row, "table_name", @row_keys)
    constraint_name = Result.value(row, "constraint_name", @row_keys)
    column_names = Result.value(row, "column_names", @row_keys)
    referenced_schema_name = Result.value(row, "referenced_schema_name", @row_keys)
    referenced_table_name = Result.value(row, "referenced_table_name", @row_keys)
    referenced_column_names = Result.value(row, "referenced_column_names", @row_keys)

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
          rule :: map(),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, rule, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres scoped foreign keys",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        rule: rule,
        reason: reason
      }
    }
  end
end
