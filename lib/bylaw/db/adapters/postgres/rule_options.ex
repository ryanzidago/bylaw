defmodule Bylaw.Db.Adapters.Postgres.RuleOptions do
  @moduledoc false

  @type matcher_value :: String.t() | Regex.t()
  @type matcher_values :: matcher_value() | list(matcher_value())
  @type matcher :: keyword(matcher_values())
  @type rule :: %{only: list(matcher()), except: list(matcher())}

  @plural_keys %{
    schemas: :schema,
    tables: :table,
    constraints: :constraint,
    columns: :column,
    types: :type,
    referenced_schemas: :referenced_schema,
    referenced_tables: :referenced_table,
    referenced_columns: :referenced_column
  }

  @doc false
  @spec keyword_list!(term(), atom()) :: keyword()
  def keyword_list!(opts, check) when is_list(opts) do
    if Keyword.keyword?(opts) do
      opts
    else
      raise ArgumentError, "expected #{check} opts to be a keyword list, got: #{inspect(opts)}"
    end
  end

  def keyword_list!(opts, check) do
    raise ArgumentError, "expected #{check} opts to be a keyword list, got: #{inspect(opts)}"
  end

  @doc false
  @spec validate_allowed_keys!(keyword(), list(atom()), atom()) :: :ok
  def validate_allowed_keys!(opts, allowed_keys, check) do
    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown #{check} option: #{inspect(key)}"
      end
    end)
  end

  @doc false
  @spec reject_top_level_keys_with_rules!(keyword(), list(atom()), atom()) :: :ok
  def reject_top_level_keys_with_rules!(opts, keys, check) when is_list(opts) do
    opts
    |> top_level_key_with_rules(keys)
    |> reject_top_level_key_with_rules!(check)
  end

  defp top_level_key_with_rules(opts, keys) do
    if Keyword.has_key?(opts, :rules), do: Enum.find(keys, &Keyword.has_key?(opts, &1))
  end

  defp reject_top_level_key_with_rules!(nil, _check), do: :ok

  defp reject_top_level_key_with_rules!(key, check) do
    raise ArgumentError,
          "expected #{check} to use rule-level #{inspect(key)} when :rules is provided"
  end

  @doc false
  @spec validate_boolean_option!(keyword(), atom(), atom()) :: :ok
  def validate_boolean_option!(opts, key, check) do
    case Keyword.fetch(opts, key) do
      {:ok, value} when is_boolean(value) ->
        :ok

      {:ok, value} ->
        raise ArgumentError,
              "expected #{check} #{inspect(key)} to be a boolean, got: #{inspect(value)}"

      :error ->
        :ok
    end
  end

  @doc false
  @spec enabled?(keyword()) :: boolean()
  def enabled?(opts), do: Keyword.get(opts, :validate, true) == true

  @doc false
  @spec filter(keyword(), atom(), atom()) :: list(String.t()) | nil
  def filter(opts, key, check) do
    case Keyword.get(opts, key) do
      nil ->
        nil

      values when is_list(values) ->
        if Enum.empty?(values) or Enum.any?(values, &(not non_empty_string?(&1))) do
          raise ArgumentError,
                "expected #{check} #{inspect(key)} to be a non-empty list of strings"
        end

        values

      _value ->
        raise ArgumentError, "expected #{check} #{inspect(key)} to be a non-empty list of strings"
    end
  end

  @doc false
  @spec default_rules!(keyword(), atom(), list(atom())) :: list(rule())
  def default_rules!(opts, check, allowed_matcher_keys) do
    case Keyword.fetch(opts, :rules) do
      {:ok, rules} -> rules!(rules, check, allowed_matcher_keys, [], fn _rule -> %{} end)
      :error -> [%{only: [], except: matchers(opts, :except, check, allowed_matcher_keys)}]
    end
  end

  @doc false
  @spec rules!(
          term(),
          atom(),
          list(atom()),
          list(atom()),
          (keyword() -> map())
        ) :: list(map())
  def rules!(rules, check, allowed_matcher_keys, payload_keys, payload_fun) when is_list(rules) do
    if Enum.empty?(rules) or Enum.any?(rules, &(not Keyword.keyword?(&1))) do
      raise_rules_error!(check)
    end

    Enum.map(rules, &rule!(&1, check, allowed_matcher_keys, payload_keys, payload_fun))
  end

  def rules!(_rules, check, _allowed_matcher_keys, _payload_keys, _payload_fun) do
    raise_rules_error!(check)
  end

  @doc false
  @spec matchers(keyword(), atom(), atom(), list(atom())) :: list(matcher())
  def matchers(opts, key, check, allowed_matcher_keys) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> matchers!(value, check, key, allowed_matcher_keys)
      :error -> []
    end
  end

  @doc false
  @spec in_rule_scope?(term(), rule(), (term(), atom() -> term())) :: boolean()
  def in_rule_scope?(row, rule, value_fun) do
    (Enum.empty?(rule.only) or matches_any?(row, rule.only, value_fun)) and
      not matches_any?(row, rule.except, value_fun)
  end

  @doc false
  @spec matches_any?(term(), list(matcher()), (term(), atom() -> term())) :: boolean()
  def matches_any?(_row, [], _value_fun), do: false

  def matches_any?(row, matchers, value_fun),
    do: Enum.any?(matchers, &matches?(row, &1, value_fun))

  defp rule!(rule, check, allowed_matcher_keys, payload_keys, payload_fun) do
    allowed_rule_keys = [:only, :where, :except] ++ payload_keys

    Enum.each(rule, fn {key, _value} ->
      if key not in allowed_rule_keys do
        raise ArgumentError, "unknown #{check} rule option: #{inspect(key)}"
      end
    end)

    if Keyword.has_key?(rule, :only) and Keyword.has_key?(rule, :where) do
      raise ArgumentError, "expected #{check} rule to include :only or :where, not both"
    end

    rule
    |> payload_fun.()
    |> Map.merge(%{
      only: matchers(rule, scope_key(rule), check, allowed_matcher_keys),
      except: matchers(rule, :except, check, allowed_matcher_keys)
    })
  end

  defp scope_key(rule) do
    if Keyword.has_key?(rule, :only), do: :only, else: :where
  end

  defp matchers!(value, check, key, allowed_matcher_keys) when is_list(value) do
    cond do
      Keyword.keyword?(value) ->
        [matcher!(value, check, key, allowed_matcher_keys)]

      Enum.empty?(value) ->
        raise_matchers_error!(check, key)

      Enum.all?(value, &Keyword.keyword?/1) ->
        Enum.map(value, &matcher!(&1, check, key, allowed_matcher_keys))

      true ->
        raise_matchers_error!(check, key)
    end
  end

  defp matchers!(_value, check, key, _allowed_matcher_keys), do: raise_matchers_error!(check, key)

  defp matcher!(matcher, check, key, allowed_matcher_keys) do
    if Enum.empty?(matcher) do
      raise_matchers_error!(check, key)
    end

    Enum.map(matcher, fn {matcher_key, matcher_value} ->
      normalized_key = Map.get(@plural_keys, matcher_key, matcher_key)

      if normalized_key not in allowed_matcher_keys do
        raise ArgumentError,
              "unknown #{check} #{inspect(key)} matcher option: #{inspect(matcher_key)}"
      end

      matcher_values!(check, key, matcher_key, matcher_value)
      {normalized_key, matcher_value}
    end)
  end

  defp matcher_values!(check, key, matcher_key, values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not matcher_value?(&1))) do
      raise_matcher_values_error!(check, key, matcher_key)
    end
  end

  defp matcher_values!(check, key, matcher_key, value) do
    if not matcher_value?(value) do
      raise_matcher_values_error!(check, key, matcher_key)
    end
  end

  defp matcher_value?(%Regex{}), do: true
  defp matcher_value?(value), do: non_empty_string?(value)

  defp matches?(row, matcher, value_fun) do
    Enum.all?(matcher, fn {key, expected} ->
      row
      |> value_fun.(key)
      |> matches_value?(expected)
    end)
  end

  defp matches_value?(values, expected) when is_list(values) do
    Enum.any?(values, &matches_value?(&1, expected))
  end

  defp matches_value?(nil, _expected), do: false

  defp matches_value?(value, expected) when is_list(expected) do
    Enum.any?(expected, &matches_value?(value, &1))
  end

  defp matches_value?(value, %Regex{} = regex), do: Regex.match?(regex, value)
  defp matches_value?(value, expected), do: value == expected

  defp raise_rules_error!(check) do
    raise ArgumentError, "expected #{check} :rules to be a non-empty list of keyword rules"
  end

  defp raise_matchers_error!(check, key) do
    raise ArgumentError,
          "expected #{check} #{inspect(key)} to be a matcher or non-empty list of matchers"
  end

  defp raise_matcher_values_error!(check, key, matcher_key) do
    raise ArgumentError,
          "expected #{check} #{inspect(key)} #{inspect(matcher_key)} to be a matcher value or non-empty list of matcher values"
  end

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0
end
