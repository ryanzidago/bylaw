defmodule Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType do
  @moduledoc """
  Validates that Postgres primary key columns use expected types.

  Use `rules: [...]` to require different primary key types for scoped groups of
  tables. A rule applies when a table matches any matcher in `where`; keys inside
  one matcher are combined. Matching rules accumulate, so the same table can be
  validated by more than one rule.

      {PrimaryKeyType,
       rules: [
         [type: "uuid"],
         [
           where: [[schema: "legacy"], [table: ~r/^audit_/]],
           types: ["bigint", "integer"]
         ]
       ],
       except: [[table: "schema_migrations"]]}

  For the common one-rule case, pass `type: "uuid"` or
  `types: ["uuid", "bigint"]` directly.
  """

  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Check
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  @query """
  SELECT
    namespace.nspname AS schema_name,
    table_class.relname AS table_name,
    attribute.attname AS column_name,
    pg_catalog.format_type(attribute.atttypid, attribute.atttypmod) AS column_type
  FROM pg_catalog.pg_index AS index_record
  JOIN pg_catalog.pg_class AS table_class
    ON table_class.oid = index_record.indrelid
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = table_class.relnamespace
  JOIN unnest(index_record.indkey) WITH ORDINALITY AS key(attnum, position)
    ON true
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = index_record.indrelid
   AND attribute.attnum = key.attnum
  WHERE index_record.indisprimary
    AND table_class.relkind IN ('r', 'p')
    AND namespace.nspname <> 'information_schema'
    AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
  ORDER BY schema_name, table_name, key.position
  """

  @type matcher_value :: String.t() | Regex.t()
  @type matcher_values :: matcher_value() | list(matcher_value())
  @type matcher ::
          list(
            {:schema, matcher_values()}
            | {:schemas, list(matcher_value())}
            | {:table, matcher_values()}
            | {:tables, list(matcher_value())}
            | {:column, matcher_values()}
            | {:columns, list(matcher_value())}
          )
  @type rule ::
          list(
            {:type, String.t()}
            | {:types, list(String.t())}
            | {:where, matcher() | list(matcher())}
            | {:except, matcher() | list(matcher())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:type, String.t()}
          | {:types, list(String.t())}
          | {:rules, list(rule())}
          | {:except, matcher() | list(matcher())}

  @type check_opts :: list(check_opt())
  @type normalized_rule :: %{
          types: list(String.t()),
          where: list(matcher()),
          except: list(matcher())
        }
  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }

  @row_keys %{
    "column_name" => :column_name,
    "column_type" => :column_type,
    "schema_name" => :schema_name,
    "table_name" => :table_name
  }

  @doc """
  Returns the option namespace used by this check.
  """
  @impl Bylaw.Db.Check
  @spec name() :: :primary_key_type
  def name, do: :primary_key_type

  @doc """
  Validates that primary key columns matched by each rule use the rule's types.

  The check is enabled by default. Pass `validate: false` to skip it. Validation
  requires either `type: ...`, `types: [...]`, or `rules: [...]`.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
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
    global_except = matchers(opts, :except)

    rules
    |> Enum.flat_map(&rule_issues(target, &1, global_except))
    |> result()
  end

  defp rule_issues(target, rule, global_except) do
    case Postgres.query(target, @query, [], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.filter(&issue_row?(&1, rule, global_except))
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
            "expected primary_key_type opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :type, :types, :rules, :except]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown primary_key_type option: #{inspect(key)}"
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
              "expected primary_key_type #{inspect(key)} to be a boolean, got: #{inspect(value)}"

      :error ->
        :ok
    end
  end

  defp normalize_rules!(opts) do
    case selected_rule_keys(opts) do
      [:type] ->
        [%{types: [type!(Keyword.fetch!(opts, :type))], where: [], except: []}]

      [:types] ->
        [%{types: types!(Keyword.fetch!(opts, :types)), where: [], except: []}]

      [:rules] ->
        opts
        |> Keyword.fetch!(:rules)
        |> rules!()

      [] ->
        raise ArgumentError, "expected primary_key_type to include :type, :types, or :rules"

      [:type, :types] ->
        raise ArgumentError, "expected primary_key_type to include :type or :types, not both"

      _keys ->
        raise ArgumentError,
              "expected primary_key_type to include :type, :types, or :rules, not both"
    end
  end

  defp selected_rule_keys(opts) do
    Enum.filter([:type, :types, :rules], &Keyword.has_key?(opts, &1))
  end

  defp rules!(rules) when is_list(rules) do
    if Enum.empty?(rules) or Enum.any?(rules, &(not Keyword.keyword?(&1))) do
      raise_rules_error!()
    end

    Enum.map(rules, &rule!/1)
  end

  defp rules!(_rules), do: raise_rules_error!()

  defp rule!(rule) do
    allowed_keys = [:type, :types, :where, :except]

    Enum.each(rule, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown primary_key_type rule option: #{inspect(key)}"
      end
    end)

    has_type? = Keyword.has_key?(rule, :type)
    has_types? = Keyword.has_key?(rule, :types)

    cond do
      has_type? and has_types? ->
        raise ArgumentError, "expected primary_key_type rule to include :type or :types, not both"

      has_type? ->
        %{
          types: [type!(Keyword.fetch!(rule, :type))],
          where: matchers(rule, :where),
          except: matchers(rule, :except)
        }

      has_types? ->
        %{
          types: types!(Keyword.fetch!(rule, :types)),
          where: matchers(rule, :where),
          except: matchers(rule, :except)
        }

      true ->
        raise ArgumentError, "expected primary_key_type rule to include :type or :types"
    end
  end

  defp type!(value) do
    if non_empty_string?(value) do
      value
    else
      raise_types_error!()
    end
  end

  defp types!(values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_types_error!()
    end

    values
  end

  defp types!(_values), do: raise_types_error!()

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
    allowed_keys = [:schema, :schemas, :table, :tables, :column, :columns]

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
    matches_table_by_rule?(row, rule) and
      not matches_any?(rule.except, row) and
      not matches_any?(global_except, row)
  end

  defp issue_row?(row, rule, global_except) do
    matched_by_rule?(row, rule, global_except) and value(row, "column_type") not in rule.types
  end

  defp matches_table_by_rule?(row, rule) do
    Enum.empty?(rule.where) or matches_any?(rule.where, row)
  end

  defp matches_any?([], _row), do: false

  defp matches_any?(matchers, row) do
    Enum.any?(matchers, &matches?(row, &1))
  end

  defp matches?(row, matcher) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    column_name = value(row, "column_name")

    Enum.all?(matcher, fn
      {:schema, value} -> matches_value?(schema_name, value)
      {:schemas, values} -> matches_value?(schema_name, values)
      {:table, value} -> matches_value?(table_name, value)
      {:tables, values} -> matches_value?(table_name, values)
      {:column, value} -> matches_value?(column_name, value)
      {:columns, values} -> matches_value?(column_name, values)
    end)
  end

  defp matches_value?(value, %Regex{} = pattern), do: Regex.match?(pattern, value)
  defp matches_value?(value, expected) when is_binary(expected), do: value == expected

  defp matches_value?(value, expected) when is_list(expected),
    do: Enum.any?(expected, &matches_value?(value, &1))

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_rules_error! do
    raise ArgumentError,
          "expected primary_key_type :rules to be a non-empty list of keyword rules"
  end

  defp raise_types_error! do
    raise ArgumentError, "expected primary_key_type :type or :types to be non-empty strings"
  end

  defp raise_matchers_error!(key) do
    raise ArgumentError,
          "expected primary_key_type #{inspect(key)} to be a matcher or non-empty list of matchers"
  end

  @spec issue(target :: Target.t(), row :: result_row(), rule :: normalized_rule()) :: Issue.t()
  defp issue(target, row, rule) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    column_name = value(row, "column_name")
    column_type = value(row, "column_type")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected #{schema_name}.#{table_name} primary key column #{column_name} to use type #{format_types(rule.types)}, got #{column_type}",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        column: column_name,
        actual_type: column_type,
        expected_types: rule.types,
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
      message: "could not inspect Postgres primary key types",
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
      types: rule.types,
      where: rule.where,
      except: rule.except
    }
  end

  defp format_types([type]), do: type
  defp format_types(types), do: Enum.join(types, " or ")

  defp value(row, key) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(row, Map.fetch!(@row_keys, key))
    end
  end
end
