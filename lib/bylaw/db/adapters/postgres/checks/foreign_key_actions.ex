defmodule Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActions do
  @moduledoc """
  Validates Postgres foreign key `ON DELETE` and `ON UPDATE` actions.

  Use a rule without `:only` when every foreign key in scope should use the same
  action:

      {ForeignKeyActions,
       rules: [[on_delete: :cascade]]}

  Use `rules: [...]` for scoped policy. A foreign key can match more than one
  rule, and matching rules accumulate.

      {ForeignKeyActions,
       rules: [
         [
          only: [[table: "messages"], [referenced_table: "conversations"]],
           on_delete: :cascade
         ],
         [
          only: [referenced_table: "lookup_statuses"],
           on_delete: :restrict,
           on_update: :restrict
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
            | {:table, matcher_values()}
            | {:constraint, matcher_values()}
            | {:column, matcher_values()}
            | {:referenced_schema, matcher_values()}
            | {:referenced_table, matcher_values()}
            | {:referenced_column, matcher_values()}
          )
  @type rule ::
          list(
            {:only, matcher() | list(matcher())}
            | {:except, matcher() | list(matcher())}
            | {:on_delete, action()}
            | {:on_update, action()}
          )
  @type check_opt ::
          {:validate, boolean()}
          | {:rules, list(rule())}

  @type check_opts :: list(check_opt())
  @type normalized_rule :: %{
          only: list(matcher()),
          except: list(matcher()),
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
  [...]` for scoped policy. Use rule-level `:only` and `:except` matchers to
  narrow or exclude the inspected foreign keys.
  """
  @impl Bylaw.Db.Check
  @spec validate(target :: Target.t(), opts :: check_opts()) :: Check.result()
  def validate(%Target{adapter: Postgres} = target, opts) when is_list(opts) do
    opts = check_opts!(opts)

    if RuleOptions.enabled?(opts) do
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
    rules = normalize_rules!(opts)
    schemas = RuleOptions.filter(opts, :schemas, :foreign_key_actions)
    tables = RuleOptions.filter(opts, :tables, :foreign_key_actions)

    case Postgres.query(target, @query, [schemas, tables], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.flat_map(&row_issues(target, &1, rules))
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
    RuleOptions.keyword_list!(opts, :foreign_key_actions)

    RuleOptions.validate_allowed_keys!(
      opts,
      [:validate, :rules, :on_delete, :on_update],
      :foreign_key_actions
    )

    RuleOptions.validate_boolean_option!(opts, :validate, :foreign_key_actions)

    if RuleOptions.enabled?(opts) do
      RuleOptions.reject_top_level_keys_with_rules!(
        opts,
        [:on_delete, :on_update],
        :foreign_key_actions
      )

      normalize_rules!(opts)
    end

    opts
  end

  defp normalize_rules!(opts) do
    cond do
      Keyword.has_key?(opts, :rules) and
          (Keyword.has_key?(opts, :on_delete) or Keyword.has_key?(opts, :on_update)) ->
        raise ArgumentError,
              "expected foreign_key_actions to include global actions or :rules, not both"

      Keyword.has_key?(opts, :rules) ->
        opts
        |> Keyword.fetch!(:rules)
        |> RuleOptions.rules!(
          :foreign_key_actions,
          allowed_matcher_keys(),
          [:on_delete, :on_update],
          &rule_payload!/1
        )

      Keyword.has_key?(opts, :on_delete) or Keyword.has_key?(opts, :on_update) ->
        [
          %{
            only: [],
            except: [],
            on_delete: action!(opts, :on_delete),
            on_update: action!(opts, :on_update)
          }
        ]

      true ->
        raise ArgumentError,
              "expected foreign_key_actions to include :on_delete, :on_update, or :rules"
    end
  end

  defp rule_payload!(rule) do
    if not (Keyword.has_key?(rule, :on_delete) or Keyword.has_key?(rule, :on_update)) do
      raise ArgumentError,
            "expected foreign_key_actions rule to include :on_delete or :on_update"
    end

    %{
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

  defp matched_rules(row, rules) do
    Enum.filter(rules, fn rule -> RuleOptions.in_rule_scope?(row, rule, &matcher_value/2) end)
  end

  defp matcher_value(row, :schema), do: value(row, "schema_name")
  defp matcher_value(row, :table), do: value(row, "table_name")
  defp matcher_value(row, :constraint), do: value(row, "constraint_name")
  defp matcher_value(row, :column), do: value(row, "column_names")
  defp matcher_value(row, :referenced_schema), do: value(row, "referenced_schema_name")
  defp matcher_value(row, :referenced_table), do: value(row, "referenced_table_name")
  defp matcher_value(row, :referenced_column), do: value(row, "referenced_column_names")

  defp allowed_matcher_keys do
    [
      :schema,
      :table,
      :constraint,
      :column,
      :referenced_schema,
      :referenced_table,
      :referenced_column
    ]
  end

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
          rules :: list(normalized_rule()),
          reason :: term()
        ) :: Issue.t()
  defp query_error_issue(target, rules, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect Postgres foreign key actions",
      meta: %{
        repo: target.repo,
        dynamic_repo: target.dynamic_repo,
        rules: rules,
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
