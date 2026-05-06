defmodule Bylaw.Db.Adapters.Postgres.Checks.ForbiddenColumnTypes do
  @moduledoc """
  Validates that Postgres columns do not use configured forbidden types.

  By default the check inspects all non-system schemas in a Postgres target. Use
  `rules: [...]` to configure forbidden types for scoped groups of columns:

      {ForbiddenColumnTypes,
       rules: [
         [
           only: [schema: "public"],
           types: [
             [type: "json", prefer: "jsonb", reason: "jsonb supports common indexing patterns"],
             [type: ~r/^character\\(/, prefer: "text"]
           ],
           except: [[table: "webhook_events", column: "raw_payload"]]
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
            | {:table, matcher_values()}
            | {:column, matcher_values()}
            | {:type, matcher_values()}
          )
  @type scope_rule ::
          list(
            {:only, matcher() | list(matcher())}
            | {:except, matcher() | list(matcher())}
            | {:types, list(type_rule())}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:rules, list(scope_rule())}

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
  requires `rules: [[types: [...]]]`; each type rule can be a string, regex, or
  keyword rule with optional `:prefer` and `:reason` guidance.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if RuleOptions.enabled?(opts) do
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
    rules = normalize_scope_rules!(opts)
    schemas = RuleOptions.filter(opts, :schemas, :forbidden_column_types)
    tables = RuleOptions.filter(opts, :tables, :forbidden_column_types)

    case Postgres.query(target, @query, [schemas, tables], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.flat_map(&issues_for_row(target, &1, rules))
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
    RuleOptions.keyword_list!(opts, :forbidden_column_types)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :types, :schemas, :tables, :except],
      :forbidden_column_types
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :forbidden_column_types)

    if RuleOptions.enabled?(opts) do
      RuleOptions.reject_top_level_keys_with_rules!(
        opts,
        [:types, :schemas, :tables, :except],
        :forbidden_column_types
      )

      normalize_scope_rules!(opts)
      RuleOptions.filter(opts, :schemas, :forbidden_column_types)
      RuleOptions.filter(opts, :tables, :forbidden_column_types)
    end

    opts
  end

  defp normalize_scope_rules!(opts) do
    cond do
      Keyword.has_key?(opts, :rules) ->
        opts
        |> Keyword.fetch!(:rules)
        |> RuleOptions.rules!(
          :forbidden_column_types,
          allowed_matcher_keys(),
          [:types],
          &scope_rule_payload!/1
        )

      Keyword.has_key?(opts, :types) ->
        [
          %{
            types: type_rules!(Keyword.fetch!(opts, :types)),
            only: legacy_only(opts),
            except:
              RuleOptions.matchers(opts, :except, :forbidden_column_types, allowed_matcher_keys())
          }
        ]

      true ->
        raise ArgumentError, "expected forbidden_column_types to include :types"
    end
  end

  defp legacy_only(opts) do
    matcher =
      []
      |> maybe_put_matcher(:schema, Keyword.get(opts, :schemas))
      |> maybe_put_matcher(:table, Keyword.get(opts, :tables))

    if Enum.empty?(matcher), do: [], else: [matcher]
  end

  defp maybe_put_matcher(matcher, _key, nil), do: matcher
  defp maybe_put_matcher(matcher, key, value), do: Keyword.put(matcher, key, value)

  defp scope_rule_payload!(rule) do
    if not Keyword.has_key?(rule, :types) do
      raise ArgumentError, "expected forbidden_column_types rule to include :types"
    end

    %{types: type_rules!(Keyword.fetch!(rule, :types))}
  end

  defp type_rules!(rules) when is_list(rules) do
    if Enum.empty?(rules) do
      raise_types_error!()
    end

    Enum.map(rules, &type_rule!/1)
  end

  defp type_rules!(_rules), do: raise_types_error!()

  defp type_rule!(type) when is_binary(type) and byte_size(type) > 0 do
    %{type: type, prefer: nil, reason: nil}
  end

  defp type_rule!(%Regex{} = type) do
    %{type: type, prefer: nil, reason: nil}
  end

  defp type_rule!(rule) when is_list(rule) do
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

  defp type_rule!(_rule), do: raise_types_error!()

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

  defp issues_for_row(target, row, rules) do
    rules
    |> Enum.filter(fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)
    |> Enum.flat_map(&matching_type_rules(row, &1))
    |> Enum.map(&issue(target, row, &1))
  end

  defp matching_type_rules(row, rule) do
    Enum.filter(rule.types, &type_rule_matches?(&1, value(row, "type_name")))
  end

  defp type_rule_matches?(%{type: %Regex{} = regex}, actual_type),
    do: Regex.match?(regex, actual_type)

  defp type_rule_matches?(rule, actual_type), do: rule.type == actual_type

  defp matcher_value(row, :schema), do: value(row, "schema_name")
  defp matcher_value(row, :table), do: value(row, "table_name")
  defp matcher_value(row, :column), do: value(row, "column_name")
  defp matcher_value(row, :type), do: value(row, "type_name")

  defp allowed_matcher_keys, do: [:schema, :table, :column, :type]

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
          rules :: list(map()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, rules, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres column types",
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
