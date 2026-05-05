defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActions do
  @moduledoc """
  Validates Postgres foreign key `ON DELETE` and `ON UPDATE` actions.

  Use global `:on_delete` and/or `:on_update` options when every foreign key in
  scope should use the same action:

      {ForeignKeyActions,
       schemas: ["public"],
       on_delete: :cascade}

  Use `rules: [...]` for scoped policy. A foreign key can match more than one
  rule, and matching rules accumulate.

      {ForeignKeyActions,
       rules: [
         [
           where: [[table: "messages"], [referenced_table: "conversations"]],
           on_delete: :cascade
         ],
         [
           where: [referenced_table: "lookup_statuses"],
           on_delete: :restrict,
           on_update: :restrict
         ]
       ]}
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
    constraint_record.conname AS constraint_name,
    ARRAY(
      SELECT attribute.attname
      FROM unnest(constraint_record.conkey) WITH ORDINALITY AS key(attnum, position)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = constraint_record.conrelid
       AND attribute.attnum = key.attnum
      ORDER BY key.position
    ) AS column_names,
    referenced_namespace.nspname AS referenced_schema_name,
    referenced_class.relname AS referenced_table_name,
    ARRAY(
      SELECT attribute.attname
      FROM unnest(constraint_record.confkey) WITH ORDINALITY AS key(attnum, position)
      JOIN pg_catalog.pg_attribute AS attribute
        ON attribute.attrelid = constraint_record.confrelid
       AND attribute.attnum = key.attnum
      ORDER BY key.position
    ) AS referenced_column_names,
    constraint_record.confdeltype::text AS delete_action_code,
    constraint_record.confupdtype::text AS update_action_code
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
  ORDER BY schema_name, table_name, constraint_name
  """

  @actions [:no_action, :restrict, :cascade, :set_null, :set_default]
  @action_codes %{
    "a" => :no_action,
    "r" => :restrict,
    "c" => :cascade,
    "n" => :set_null,
    "d" => :set_default
  }

  @type action :: :no_action | :restrict | :cascade | :set_null | :set_default
  @type matcher_value :: String.t() | Regex.t()
  @type matcher_values :: matcher_value() | list(matcher_value())
  @type matcher ::
          list(
            {:schema, matcher_values()}
            | {:schemas, list(matcher_value())}
            | {:table, matcher_values()}
            | {:tables, list(matcher_value())}
            | {:constraint, matcher_values()}
            | {:constraints, list(matcher_value())}
            | {:column, matcher_values()}
            | {:columns, list(matcher_value())}
            | {:referenced_schema, matcher_values()}
            | {:referenced_schemas, list(matcher_value())}
            | {:referenced_table, matcher_values()}
            | {:referenced_tables, list(matcher_value())}
            | {:referenced_column, matcher_values()}
            | {:referenced_columns, list(matcher_value())}
          )
  @type rule ::
          list(
            {:where, matcher() | list(matcher())}
            | {:on_delete, action()}
            | {:on_update, action()}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:schemas, list(String.t())}
          | {:tables, list(String.t())}
          | {:except, matcher() | list(matcher())}
          | {:on_delete, action()}
          | {:on_update, action()}
          | {:rules, list(rule())}

  @type check_opts :: list(check_opt())
  @type normalized_rule :: %{
          where: list(matcher()),
          on_delete: action() | nil,
          on_update: action() | nil
        }
  @type result_row :: %{
          optional(String.t()) => term(),
          optional(atom()) => term()
        }
  @row_keys %{
    "column_names" => :column_names,
    "constraint_name" => :constraint_name,
    "delete_action_code" => :delete_action_code,
    "referenced_column_names" => :referenced_column_names,
    "referenced_schema_name" => :referenced_schema_name,
    "referenced_table_name" => :referenced_table_name,
    "schema_name" => :schema_name,
    "table_name" => :table_name,
    "update_action_code" => :update_action_code
  }

  @doc """
  Validates that foreign keys in the target scope use configured actions.

  The check is enabled by default. Pass `validate: false` to skip it. Validation
  requires either global `:on_delete` and/or `:on_update` policy, or `rules:
  [...]` for scoped policy. Use `:schemas`, `:tables`, and `:except` to narrow
  or exclude the inspected child foreign keys.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if Keyword.get(opts, :validate, true) == true do
      validate_foreign_key_actions(target, opts)
    else
      :ok
    end
  end

  def validate(%Target{adapter: Postgres}, opts) do
    raise ArgumentError,
          "expected foreign_key_actions opts to be a keyword list, got: #{inspect(opts)}"
  end

  def validate(%Target{} = target, _opts) do
    raise ArgumentError, "expected a Postgres target, got: #{inspect(target)}"
  end

  def validate(target, _opts) do
    raise ArgumentError, "expected a database target, got: #{inspect(target)}"
  end

  defp validate_foreign_key_actions(target, opts) do
    schemas = filter(opts, :schemas)
    tables = filter(opts, :tables)
    rules = normalize_rules!(opts)
    exceptions = matchers(opts, :except)

    case Postgres.query(target, @query, [schemas, tables], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.reject(&matches_any?(&1, exceptions))
        |> Enum.flat_map(&row_issues(target, &1, rules))
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
            "expected foreign_key_actions opts to be a keyword list, got: #{inspect(opts)}"
    end

    allowed_keys = [:validate, :schemas, :tables, :except, :on_delete, :on_update, :rules]

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown foreign_key_actions option: #{inspect(key)}"
      end
    end)

    validate_boolean_option!(opts, :validate)
    validate_filter_option!(opts, :schemas)
    validate_filter_option!(opts, :tables)

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
              "expected foreign_key_actions #{inspect(key)} to be a boolean, got: #{inspect(value)}"

      :error ->
        :ok
    end
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

  defp normalize_rules!(opts) do
    has_delete? = Keyword.has_key?(opts, :on_delete)
    has_update? = Keyword.has_key?(opts, :on_update)
    has_rules? = Keyword.has_key?(opts, :rules)

    cond do
      has_rules? and (has_delete? or has_update?) ->
        raise ArgumentError,
              "expected foreign_key_actions to include global actions or :rules, not both"

      has_delete? or has_update? ->
        [
          %{
            where: [],
            on_delete: action!(opts, :on_delete),
            on_update: action!(opts, :on_update)
          }
        ]

      has_rules? ->
        opts
        |> Keyword.fetch!(:rules)
        |> rules!()

      true ->
        raise ArgumentError,
              "expected foreign_key_actions to include :on_delete, :on_update, or :rules"
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
    allowed_keys = [:where, :on_delete, :on_update]

    Enum.each(rule, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown foreign_key_actions rule option: #{inspect(key)}"
      end
    end)

    if not (Keyword.has_key?(rule, :on_delete) or Keyword.has_key?(rule, :on_update)) do
      raise ArgumentError,
            "expected foreign_key_actions rule to include :on_delete or :on_update"
    end

    %{
      where: matchers(rule, :where),
      on_delete: action!(rule, :on_delete),
      on_update: action!(rule, :on_update)
    }
  end

  defp action!(opts, key) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when value in @actions ->
        value

      {:ok, value} ->
        raise ArgumentError,
              "expected foreign_key_actions #{inspect(key)} to be one of #{inspect(@actions)}, got: #{inspect(value)}"

      :error ->
        nil
    end
  end

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
    allowed_keys = [
      :schema,
      :schemas,
      :table,
      :tables,
      :constraint,
      :constraints,
      :column,
      :columns,
      :referenced_schema,
      :referenced_schemas,
      :referenced_table,
      :referenced_tables,
      :referenced_column,
      :referenced_columns
    ]

    if Enum.empty?(matcher) do
      raise_matchers_error!(key)
    end

    Enum.each(matcher, fn {matcher_key, matcher_value} ->
      if matcher_key not in allowed_keys do
        raise ArgumentError,
              "unknown foreign_key_actions #{inspect(key)} matcher option: #{inspect(matcher_key)}"
      end

      matcher_values!(key, matcher_key, matcher_value)
    end)

    matcher
  end

  defp matcher_values!(key, matcher_key, values)
       when matcher_key in [
              :schemas,
              :tables,
              :constraints,
              :columns,
              :referenced_schemas,
              :referenced_tables,
              :referenced_columns
            ] do
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

  defp matched_rules(row, rules) do
    Enum.filter(rules, fn rule ->
      Enum.empty?(rule.where) or matches_any?(row, rule.where)
    end)
  end

  defp matches_any?(_row, []), do: false
  defp matches_any?(row, matchers), do: Enum.any?(matchers, &matches?(row, &1))

  defp matches?(row, matcher) do
    Enum.all?(matcher, fn
      {:schema, values} ->
        matches_value?(value(row, "schema_name"), values)

      {:schemas, values} ->
        matches_value?(value(row, "schema_name"), values)

      {:table, values} ->
        matches_value?(value(row, "table_name"), values)

      {:tables, values} ->
        matches_value?(value(row, "table_name"), values)

      {:constraint, values} ->
        matches_value?(value(row, "constraint_name"), values)

      {:constraints, values} ->
        matches_value?(value(row, "constraint_name"), values)

      {:column, values} ->
        matches_value?(value(row, "column_names"), values)

      {:columns, values} ->
        matches_value?(value(row, "column_names"), values)

      {:referenced_schema, values} ->
        matches_value?(value(row, "referenced_schema_name"), values)

      {:referenced_schemas, values} ->
        matches_value?(value(row, "referenced_schema_name"), values)

      {:referenced_table, values} ->
        matches_value?(value(row, "referenced_table_name"), values)

      {:referenced_tables, values} ->
        matches_value?(value(row, "referenced_table_name"), values)

      {:referenced_column, values} ->
        matches_value?(value(row, "referenced_column_names"), values)

      {:referenced_columns, values} ->
        matches_value?(value(row, "referenced_column_names"), values)
    end)
  end

  defp matches_value?(values, expected) when is_list(values) do
    Enum.any?(values, &matches_value?(&1, expected))
  end

  defp matches_value?(value, expected) when is_list(expected) do
    Enum.any?(expected, &matches_value?(value, &1))
  end

  defp matches_value?(value, %Regex{} = regex), do: Regex.match?(regex, value)
  defp matches_value?(value, expected), do: value == expected

  defp row_issues(target, row, rules) do
    row
    |> matched_rules(rules)
    |> Enum.flat_map(&rule_issues(target, row, &1))
  end

  defp rule_issues(target, row, rule) do
    []
    |> maybe_add_action_issue(target, row, rule.on_delete, delete_action(row), :delete)
    |> maybe_add_action_issue(target, row, rule.on_update, update_action(row), :update)
    |> Enum.reverse()
  end

  defp maybe_add_action_issue(issues, _target, _row, nil, _actual, _type), do: issues
  defp maybe_add_action_issue(issues, _target, _row, expected, expected, _type), do: issues

  defp maybe_add_action_issue(issues, target, row, expected, actual, type) do
    [issue(target, row, expected, actual, type) | issues]
  end

  defp delete_action(row), do: action(value(row, "delete_action_code"))
  defp update_action(row), do: action(value(row, "update_action_code"))

  defp action(code), do: Map.fetch!(@action_codes, to_string(code))

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0

  defp raise_filter_error!(key) do
    raise ArgumentError,
          "expected foreign_key_actions #{inspect(key)} to be a non-empty list of strings"
  end

  defp raise_rules_error! do
    raise ArgumentError,
          "expected foreign_key_actions :rules to be a non-empty list of keyword rules"
  end

  defp raise_matchers_error!(key) do
    raise ArgumentError,
          "expected foreign_key_actions #{inspect(key)} to be a matcher or non-empty list of matchers"
  end

  defp raise_matcher_values_error!(key, matcher_key) do
    raise ArgumentError,
          "expected foreign_key_actions #{inspect(key)} #{inspect(matcher_key)} to be a matcher value or non-empty list of matcher values"
  end

  @spec issue(
          target :: Target.t(),
          row :: result_row(),
          expected :: action(),
          actual :: action(),
          type :: :delete | :update
        ) :: Issue.t()
  defp issue(target, row, expected, actual, type) do
    schema_name = value(row, "schema_name")
    table_name = value(row, "table_name")
    constraint_name = value(row, "constraint_name")

    %Issue{
      check: __MODULE__,
      target: target,
      message:
        "expected foreign key #{constraint_name} on #{schema_name}.#{table_name} to use ON #{action_type(type)} #{format_action(expected)}, got: #{format_action(actual)}",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schema: schema_name,
        table: table_name,
        constraint: constraint_name,
        columns: value(row, "column_names"),
        referenced_schema: value(row, "referenced_schema_name"),
        referenced_table: value(row, "referenced_table_name"),
        referenced_columns: value(row, "referenced_column_names")
      }
    }
  end

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
      message: "could not inspect Postgres foreign key actions",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        schemas: schemas,
        tables: tables,
        rules: rules,
        except: exceptions,
        reason: reason
      }
    }
  end

  defp action_type(:delete), do: "DELETE"
  defp action_type(:update), do: "UPDATE"

  defp format_action(:no_action), do: "NO ACTION"
  defp format_action(:restrict), do: "RESTRICT"
  defp format_action(:cascade), do: "CASCADE"
  defp format_action(:set_null), do: "SET NULL"
  defp format_action(:set_default), do: "SET DEFAULT"

  defp value(row, key) do
    case Map.fetch(row, key) do
      {:ok, value} -> value
      :error -> Map.fetch!(row, Map.fetch!(@row_keys, key))
    end
  end
end
