defmodule Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns do
  @moduledoc """
  Validates that Postgres tables include required columns.

  ## Examples

  With `rules: [[where: [schemas: ["public"]], columns: ["tenant_id"]]]`, before:

  ```sql
  CREATE TABLE invoices (
    id uuid PRIMARY KEY,
    amount numeric NOT NULL
  );
  ```

  Tables without the project-standard scope column are easy to query or mutate
  without tenant filtering.

  After, add the required column:

  ```sql
  CREATE TABLE invoices (
    id uuid PRIMARY KEY,
    tenant_id uuid NOT NULL,
    amount numeric NOT NULL
  );
  ```

  The table can participate in the same scoping, authorization, and cleanup
  patterns as the rest of the schema.

  ## Notes

  The check only verifies column presence. It does not validate type,
  nullability, indexes, or constraints for required columns.

  ## Options

  Use `rules: [...]` to require columns for scoped groups of tables. A rule
  applies when a table matches any matcher in `where`; keys inside one matcher
  are combined. Matching rules accumulate, so the same table can be validated by
  more than one rule.

  ```elixir
  {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
   rules: [
     [
       columns: ["inserted_at", "updated_at"],
       except: [[tables: ["schema_migrations"]]]
     ],
     [
       where: [
         [schemas: ["audit"]],
         [schemas: ["billing"], tables: [~r/^invoice_/]]
       ],
       columns: ["tenant_id"]
     ]
   ]}
  ```

  Use rule-level `except: [...]` for exclusions.

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

  @type matcher_value :: String.t() | Regex.t()
  @type matcher_values :: list(matcher_value())
  @type matcher :: list({:schema, matcher_values()} | {:table, matcher_values()})
  @type rule ::
          list(
            {:columns, list(String.t())}
            | {:where, matcher() | list(matcher())}
            | {:except, matcher() | list(matcher())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:rules, list(rule())}
          | {:except, matcher() | list(matcher())}

  @type check_opts :: list(check_opt())
  @type normalized_rule :: %{
          columns: list(String.t()),
          where: list(matcher()),
          except: list(matcher())
        }
  @row_keys %{
    "missing_columns" => :missing_columns,
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
    rules = normalize_rules!(opts)
    global_except = RuleOptions.matchers(opts, :except, :required_columns, allowed_matcher_keys())

    rules
    |> Enum.flat_map(&rule_issues(target, &1, global_except))
    |> Result.to_check_result()
  end

  defp rule_issues(target, rule, global_except) do
    case Postgres.query(target, @query, [rule.columns], []) do
      {:ok, result} ->
        result
        |> Result.rows()
        |> Enum.filter(&matched_by_rule?(&1, rule, global_except))
        |> Enum.map(&issue(target, &1, rule))

      {:error, reason} ->
        [query_error_issue(target, rule, global_except, reason)]
    end
  end

  defp check_opts!(opts) do
    RuleOptions.keyword_list!(opts, :required_columns)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :columns, :rules, :except],
      :required_columns
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :required_columns)

    if RuleOptions.enabled?(opts) do
      RuleOptions.reject_top_level_keys_with_rules!(opts, [:columns, :except], :required_columns)
      normalize_rules!(opts)
      RuleOptions.matchers(opts, :except, :required_columns, allowed_matcher_keys())
    end

    opts
  end

  defp normalize_rules!(opts) do
    has_rules? = Keyword.has_key?(opts, :rules)
    has_columns? = Keyword.has_key?(opts, :columns)

    cond do
      has_rules? and has_columns? ->
        raise ArgumentError, "expected required_columns to include :columns or :rules, not both"

      has_rules? ->
        opts
        |> Keyword.fetch!(:rules)
        |> RuleOptions.rules!(
          :required_columns,
          allowed_matcher_keys(),
          [:columns],
          &rule_payload!/1
        )

      has_columns? ->
        [%{columns: columns!(Keyword.fetch!(opts, :columns)), where: [], except: []}]

      true ->
        raise ArgumentError, "expected required_columns to include :columns or :rules"
    end
  end

  defp rule_payload!(rule) do
    if not Keyword.has_key?(rule, :columns) do
      raise ArgumentError, "expected required_columns rule to include :columns"
    end

    %{columns: columns!(Keyword.fetch!(rule, :columns))}
  end

  defp columns!(values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_columns_error!()
    end

    values
  end

  defp columns!(_values), do: raise_columns_error!()

  defp matched_by_rule?(row, rule, global_except) do
    RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) and
      not RuleOptions.matches_any?(row, global_except, &matcher_value/2)
  end

  defp matcher_value(row, :schema), do: Result.value(row, "schema_name", @row_keys)
  defp matcher_value(row, :table), do: Result.value(row, "table_name", @row_keys)

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_columns_error! do
    raise ArgumentError, "expected required_columns :columns to be a non-empty list of strings"
  end

  defp allowed_matcher_keys, do: [:schema, :table]

  @spec issue(target :: Target.t(), row :: Result.row(), rule :: normalized_rule()) :: Issue.t()
  defp issue(target, row, rule) do
    schema_name = Result.value(row, "schema_name", @row_keys)
    table_name = Result.value(row, "table_name", @row_keys)
    missing_columns = Result.value(row, "missing_columns", @row_keys)

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
        missing_columns: missing_columns,
        rule: rule_meta(rule)
      }
    }
  end

  @spec query_error_issue(
          target :: Target.t(),
          rule :: normalized_rule(),
          global_except :: list(matcher()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, rule, global_except, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres table columns",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        rule: rule_meta(rule),
        except: global_except,
        reason: reason
      }
    }
  end

  defp rule_meta(rule) do
    %{
      columns: rule.columns,
      where: rule.where,
      except: rule.except
    }
  end
end
