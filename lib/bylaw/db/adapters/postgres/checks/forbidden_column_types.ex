defmodule Bylaw.Db.Adapters.Postgres.Checks.ForbiddenColumnTypes do
  @moduledoc """
  Validates that Postgres columns do not use configured forbidden types.

  By default the check inspects all non-system schemas in a Postgres target.
  Pass `:schemas` or `:tables` options to narrow the scope. Use `:except` to
  allow intentional columns:

      {ForbiddenColumnTypes,
       schemas: ["public"],
       types: [
         [type: "json", prefer: "jsonb", reason: "jsonb supports common indexing patterns"],
         [type: ~r/^character\\(/, prefer: "text"]
       ],
       except: [[table: "webhook_events", column: "raw_payload"]]}
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
    pg_catalog.format_type(attribute.atttypid, attribute.atttypmod) AS type_name
  FROM pg_catalog.pg_class AS table_class
  JOIN pg_catalog.pg_namespace AS namespace
    ON namespace.oid = table_class.relnamespace
  JOIN pg_catalog.pg_attribute AS attribute
    ON attribute.attrelid = table_class.oid
  WHERE table_class.relkind IN ('r', 'p')
    AND attribute.attnum > 0
    AND NOT attribute.attisdropped
    AND namespace.nspname <> 'information_schema'
    AND namespace.nspname NOT LIKE 'pg\\_%' ESCAPE '\\'
    AND ($1::text[] IS NULL OR namespace.nspname = ANY($1))
    AND ($2::text[] IS NULL OR table_class.relname = ANY($2))
  ORDER BY schema_name, table_name, attribute.attnum
  """

  @type type_matcher :: String.t() | Regex.t()
  @type type_rule ::
          type_matcher()
          | list({:type, type_matcher()} | {:prefer, String.t()} | {:reason, String.t()})
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
            | {:type, matcher_values()}
            | {:types, list(matcher_value())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:types, list(type_rule())}
          | {:schemas, list(String.t())}
          | {:tables, list(String.t())}
          | {:except, matcher() | list(matcher())}

  @type check_opts :: list(check_opt())
  @type normalized_rule :: %{
          type: type_matcher(),
          prefer: String.t() | nil,
          reason: String.t() | nil
        }
  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "column_name" => :column_name,
    "schema_name" => :schema_name,
    "table_name" => :table_name,
    "type_name" => :type_name
  }

  @doc """
  Validates that scoped Postgres columns do not use forbidden database types.

  The check is enabled by default. Pass `validate: false` to skip it. Validation
  requires `types: [...]`, where each rule can be a string, regex, or keyword
  rule with optional `:prefer` and `:reason` guidance.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_forbidden_column_types(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected forbidden_column_types opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_forbidden_column_types(target, opts) do
    schemas = filter(opts, :schemas)
    tables = filter(opts, :tables)
    rules = rules!(Keyword.fetch!(opts, :types))
    exceptions = matchers(opts, :except)

    case Postgres.query(target, @query, [schemas, tables], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.reject(&matches_any?(&1, exceptions))
        |> Enum.flat_map(&issues_for_row(target, &1, rules))
        |> result()

      {:error, reason} ->
        {:error, [query_error_issue(target, schemas, tables, rules, exceptions, reason)]}
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
            "expected forbidden_column_types opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :types, :schemas, :tables, :except]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown forbidden_column_types option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)
    validate_filter_option!(opts, :schemas)
    validate_filter_option!(opts, :tables)

    if Keyword.get(opts, :validate, true) == true do
      validate_types_option!(opts)
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
              "expected forbidden_column_types #{inspect(key)} to be a boolean, got: #{inspect(value)}"

      :error ->
        :ok
    end
  end

  defp validate_types_option!(opts) do
    case Keyword.fetch(opts, :types) do
      {:ok, value} ->
        rules!(value)
        :ok

      :error ->
        raise ArgumentError, "expected forbidden_column_types to include :types"
    end
  end

  defp rules!(rules) when is_list(rules) do
    if Enum.empty?(rules) do
      raise_types_error!()
    end

    Enum.map(rules, &rule!/1)
  end

  defp rules!(_rules), do: raise_types_error!()

  defp rule!(type) when is_binary(type) and byte_size(type) > 0 do
    %{type: type, prefer: nil, reason: nil}
  end

  defp rule!(%Regex{} = type) do
    %{type: type, prefer: nil, reason: nil}
  end

  defp rule!(rule) when is_list(rule) do
    if not Keyword.keyword?(rule) do
      raise_types_error!()
    end

    allowed_keys = [:type, :prefer, :reason]

    Enum.each(rule, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown forbidden_column_types type rule option: #{inspect(key)}"
      end
    end)

    if not Keyword.has_key?(rule, :type) do
      raise ArgumentError, "expected forbidden_column_types type rule to include :type"
    end

    type = type_matcher!(Keyword.fetch!(rule, :type))
    prefer = optional_string!(rule, :prefer)
    reason = optional_string!(rule, :reason)

    %{type: type, prefer: prefer, reason: reason}
  end

  defp rule!(_rule), do: raise_types_error!()

  defp type_matcher!(%Regex{} = type), do: type

  defp type_matcher!(type) when is_binary(type) and byte_size(type) > 0, do: type

  defp type_matcher!(_type), do: raise_types_error!()

  defp optional_string!(rule, key) do
    case Keyword.fetch(rule, key) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 ->
        value

      {:ok, value} ->
        raise ArgumentError,
              "expected forbidden_column_types type rule #{inspect(key)} to be a non-empty string, got: #{inspect(value)}"

      :error ->
        nil
    end
  end

  defp raise_types_error! do
    raise ArgumentError,
          "expected forbidden_column_types :types to be a non-empty list of strings, regexes, or keyword type rules"
  end

  defp validate_filter_option!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, values} ->
        filter!(key, values)
        :ok

      :error ->
        :ok
    end
  end

  defp filter(opts, key) do
    values = Keyword.get(opts, key)

    filter!(key, values)
  end

  defp filter!(_key, nil), do: nil

  defp filter!(key, values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
      raise_filter_error!(key)
    end

    values
  end

  defp filter!(key, _values), do: raise_filter_error!(key)

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_filter_error!(key) do
    raise ArgumentError,
          "expected forbidden_column_types #{inspect(key)} to be a non-empty list of strings"
  end

  defp matchers(opts, key) do
    case Keyword.get(opts, key, []) do
      [] -> []
      value when is_list(value) -> matchers!(key, value)
      _value -> raise_matcher_error!(key)
    end
  end

  defp matchers!(key, value) do
    cond do
      Keyword.keyword?(value) ->
        [matcher!(key, value)]

      Enum.empty?(value) ->
        raise_matcher_error!(key)

      Enum.all?(value, &Keyword.keyword?/1) ->
        Enum.map(value, &matcher!(key, &1))

      true ->
        raise_matcher_error!(key)
    end
  end

  defp matcher!(key, matcher) do
    allowed_keys = [:schema, :schemas, :table, :tables, :column, :columns, :type, :types]

    Enum.each(matcher, fn {matcher_key, matcher_value} ->
      if matcher_key not in allowed_keys do
        raise ArgumentError,
              "unknown forbidden_column_types #{inspect(key)} matcher option: #{inspect(matcher_key)}"
      end

      matcher_values!(key, matcher_key, matcher_value)
    end)

    if Enum.empty?(matcher) do
      raise_matcher_error!(key)
    end

    matcher
  end

  defp matcher_values!(key, matcher_key, values)
       when matcher_key in [:schemas, :tables, :columns, :types] do
    if not is_list(values) or Enum.empty?(values) or Enum.any?(values, &(not matcher_value?(&1))) do
      raise_matcher_values_error!(key, matcher_key)
    end
  end

  defp matcher_values!(key, matcher_key, value) do
    if not matcher_value?(value) do
      raise_matcher_values_error!(key, matcher_key)
    end
  end

  defp matcher_value?(%Regex{}), do: true
  defp matcher_value?(value), do: non_empty_string?(value)

  defp raise_matcher_error!(key) do
    raise ArgumentError,
          "expected forbidden_column_types #{inspect(key)} to be a matcher or non-empty list of matchers"
  end

  defp raise_matcher_values_error!(key, matcher_key) do
    raise ArgumentError,
          "expected forbidden_column_types #{inspect(key)} #{inspect(matcher_key)} to be a matcher value or non-empty list of matcher values"
  end

  defp matches_any?(_row, []), do: false
  defp matches_any?(row, matchers), do: Enum.any?(matchers, &matches?(row, &1))

  defp matches?(row, matcher) do
    Enum.all?(matcher, fn
      {:schema, values} -> matches_value?(value(row, "schema_name"), values)
      {:schemas, values} -> matches_value?(value(row, "schema_name"), values)
      {:table, values} -> matches_value?(value(row, "table_name"), values)
      {:tables, values} -> matches_value?(value(row, "table_name"), values)
      {:column, values} -> matches_value?(value(row, "column_name"), values)
      {:columns, values} -> matches_value?(value(row, "column_name"), values)
      {:type, values} -> matches_value?(value(row, "type_name"), values)
      {:types, values} -> matches_value?(value(row, "type_name"), values)
    end)
  end

  defp matches_value?(value, values) when is_list(values),
    do: Enum.any?(values, &matches_value?(value, &1))

  defp matches_value?(value, %Regex{} = regex), do: Regex.match?(regex, value)
  defp matches_value?(value, expected), do: value == expected

  defp issues_for_row(target, row, rules) do
    rules
    |> Enum.filter(&rule_matches?(&1, value(row, "type_name")))
    |> Enum.map(&issue(target, row, &1))
  end

  defp rule_matches?(rule, actual_type), do: matches_value?(actual_type, rule.type)

  @spec issue(target :: Target.t(), row :: result_row(), rule :: normalized_rule()) :: Issue.t()
  defp issue(target, row, rule) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    column_name = value(row, "column_name")
    type_name = value(row, "type_name")

    %Issue{
      check: __MODULE__,
      target: target,
      message: issue_message(schema_name, table_name, column_name, type_name, rule),
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        column: column_name,
        type: type_name,
        matched_type: rule.type,
        prefer: rule.prefer,
        reason: rule.reason
      }
    }
  end

  defp issue_message(schema_name, table_name, column_name, type_name, rule) do
    "expected #{schema_name}.#{table_name}.#{column_name} not to use forbidden type #{type_name}"
    |> append_prefer(rule.prefer)
    |> append_reason(rule.reason)
  end

  defp append_prefer(message, nil), do: message
  defp append_prefer(message, prefer), do: message <> "; prefer #{prefer}"

  defp append_reason(message, nil), do: message
  defp append_reason(message, reason), do: message <> " because #{reason}"

  @spec query_error_issue(
          target :: Target.t(),
          schemas :: list(String.t()) | nil,
          tables :: list(String.t()) | nil,
          rules :: list(normalized_rule()),
          exceptions :: list(matcher()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, schemas, tables, rules, exceptions, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres column types",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schemas: schemas,
        tables: tables,
        types: rules,
        except: exceptions,
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
