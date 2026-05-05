defmodule Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns do
  @moduledoc """
  Validates that Postgres tables include required columns.

  Use `rules: [...]` to require columns for scoped groups of tables. A rule
  applies when a table matches any matcher in `where`; keys inside one matcher
  are combined. Matching rules accumulate, so the same table can be validated by
  more than one rule.

      {RequiredColumns,
       rules: [
         [columns: ["inserted_at", "updated_at"]],
         [
           where: [
             [schema: "audit"],
             [schema: "billing", table: ~r/^invoice_/]
           ],
           columns: ["tenant_id"]
         ]
       ],
       except: [[table: "schema_migrations"]]}

  For the common one-rule case, pass `columns: [...]` directly.
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
  @type matcher_values :: matcher_value() | list(matcher_value())
  @type matcher ::
          list(
            {:schema, matcher_values()}
            | {:schemas, list(matcher_value())}
            | {:table, matcher_values()}
            | {:tables, list(matcher_value())}
          )
  @type rule ::
          list(
            {:columns, list(String.t())}
            | {:where, matcher() | list(matcher())}
            | {:except, matcher() | list(matcher())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:columns, list(String.t())}
          | {:rules, list(rule())}
          | {:except, matcher() | list(matcher())}

  @type check_opts :: list(check_opt())
  @type normalized_rule :: %{
          columns: list(String.t()),
          where: list(matcher()),
          except: list(matcher())
        }
  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "missing_columns" => :missing_columns,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Returns the option namespace used by this check.
  """
  @impl Bylaw.Db.Check
  @spec name() :: :required_columns
  def name, do: :required_columns

  @doc """
  Validates that tables matched by each rule include the rule's columns.

  The check is enabled by default. Pass `validate: false` to skip it. Validation
  requires either `columns: [...]` for a single global rule or `rules: [...]` for
  one or more scoped rules.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
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
    global_except = matchers(opts, :except)

    rules
    |> Enum.flat_map(&rule_issues(target, &1, global_except))
    |> result()
  end

  defp rule_issues(target, rule, global_except) do
    case Postgres.query(target, @query, [rule.columns], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.filter(&matched_by_rule?(&1, rule, global_except))
        |> Enum.map(&issue(target, &1, rule))

      {:error, reason} ->
        [query_error_issue(target, rule, global_except, reason)]
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
            "expected required_columns opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :columns, :rules, :except]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown required_columns option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)

    if Keyword.get(opts, :validate, true) == true do
      normalize_rules!(opts)
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
              "expected required_columns #{inspect(key)} to be a boolean, got: #{inspect(value)}"

      :error ->
        :ok
    end
  end

  defp normalize_rules!(opts) do
    has_columns? = Keyword.has_key?(opts, :columns)
    has_rules? = Keyword.has_key?(opts, :rules)

    cond do
      has_columns? and has_rules? ->
        raise ArgumentError, "expected required_columns to include :columns or :rules, not both"

      has_columns? ->
        [%{columns: columns!(Keyword.fetch!(opts, :columns)), where: [], except: []}]

      has_rules? ->
        opts
        |> Keyword.fetch!(:rules)
        |> rules!()

      true ->
        raise ArgumentError, "expected required_columns to include :columns or :rules"
    end
  end

  defp rules!(rules) when is_list(rules) do
    if Enum.empty?(rules) or Enum.any?(rules, &(not Keyword.keyword?(&1))) do
      raise_rules_error!()
    end

    Enum.map(rules, &rule!/1)
  end

  defp rules!(_rules), do: raise_rules_error!()

  defp rule!(rule) do
    allowed_keys = [:columns, :where, :except]

    Enum.each(rule, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown required_columns rule option: #{inspect(key)}"
      end
    end)

    if not Keyword.has_key?(rule, :columns) do
      raise ArgumentError, "expected required_columns rule to include :columns"
    end

    %{
      columns: columns!(Keyword.fetch!(rule, :columns)),
      where: matchers(rule, :where),
      except: matchers(rule, :except)
    }
  end

  defp columns!(values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_columns_error!()
    end

    values
  end

  defp columns!(_values), do: raise_columns_error!()

  defp matchers(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> matchers!(key, value)
      :error -> []
    end
  end

  defp matchers!(key, value) when is_list(value) do
    cond do
      Keyword.keyword?(value) ->
        [matcher!(key, value)]

      Enum.empty?(value) ->
        raise_matchers_error!(key)

      Enum.all?(value, &Keyword.keyword?/1) ->
        Enum.map(value, &matcher!(key, &1))

      true ->
        raise_matchers_error!(key)
    end
  end

  defp matchers!(key, _value), do: raise_matchers_error!(key)

  defp matcher!(key, matcher) do
    allowed_keys = [:schema, :schemas, :table, :tables]

    if Enum.empty?(matcher) do
      raise_matchers_error!(key)
    end

    Enum.each(matcher, fn {matcher_key, value} ->
      if matcher_key not in allowed_keys or not matcher_value?(value) do
        raise_matchers_error!(key)
      end
    end)

    matcher
  end

  defp matcher_value?(%Regex{}), do: true
  defp matcher_value?(value) when is_binary(value), do: non_empty_string?(value)

  defp matcher_value?(values) when is_list(values) do
    not Enum.empty?(values) and Enum.all?(values, &matcher_value?/1)
  end

  defp matcher_value?(_value), do: false

  defp matched_by_rule?(row, rule, global_except) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")

    (Enum.empty?(rule.where) or matches_any?(rule.where, schema_name, table_name)) and
      not matches_any?(rule.except, schema_name, table_name) and
      not matches_any?(global_except, schema_name, table_name)
  end

  defp matches_any?([], _schema_name, _table_name), do: false

  defp matches_any?(matchers, schema_name, table_name) do
    Enum.any?(matchers, &matches?(schema_name, table_name, &1))
  end

  defp matches?(schema_name, table_name, matcher) do
    Enum.all?(matcher, fn
      {:schema, value} -> matches_value?(schema_name, value)
      {:schemas, values} -> matches_value?(schema_name, values)
      {:table, value} -> matches_value?(table_name, value)
      {:tables, values} -> matches_value?(table_name, values)
    end)
  end

  defp matches_value?(value, %Regex{} = pattern), do: Regex.match?(pattern, value)
  defp matches_value?(value, expected) when is_binary(expected), do: value == expected

  defp matches_value?(value, expected) when is_list(expected),
    do: Enum.any?(expected, &matches_value?(value, &1))

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_rules_error! do
    raise ArgumentError,
          "expected required_columns :rules to be a non-empty list of keyword rules"
  end

  defp raise_columns_error! do
    raise ArgumentError, "expected required_columns :columns to be a non-empty list of strings"
  end

  defp raise_matchers_error!(key) do
    raise ArgumentError,
          "expected required_columns #{inspect(key)} to be a matcher or non-empty list of matchers"
  end

  @spec issue(target :: Target.t(), row :: result_row(), rule :: normalized_rule()) :: Issue.t()
  defp issue(target, row, rule) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    missing_columns = value(row, "missing_columns")

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

  defp value(row, key) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(row, Map.fetch!(@row_keys, key))
    end
  end
end
