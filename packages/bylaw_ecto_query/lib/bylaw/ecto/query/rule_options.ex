defmodule Bylaw.Ecto.Query.RuleOptions do
  @moduledoc false

  alias Bylaw.Ecto.Query.Introspection

  @type matcher_value :: module() | atom() | String.t() | Regex.t()
  @type matcher_values :: matcher_value() | list(matcher_value())
  @type matcher :: keyword(matcher_values())
  @type rule :: %{only: list(matcher()), except: list(matcher())}

  @allowed_matcher_keys [:ecto_schema, :table, :db_schema, :operation]

  @spec validate_allowed_options!(keyword(), atom(), list(atom())) :: :ok
  def validate_allowed_options!(opts, check, payload_keys) do
    validate_top_level_keys!(opts, check, payload_keys)
  end

  @spec default_rules!(keyword(), atom(), list(atom()), (keyword() -> map())) :: list(map())
  def default_rules!(opts, check, payload_keys, payload_fun) do
    validate_allowed_options!(opts, check, payload_keys)

    case Keyword.fetch(opts, :rules) do
      {:ok, rules} ->
        reject_top_level_payload_keys_with_rules!(opts, check, payload_keys)
        rules!(rules, check, payload_keys, payload_fun)

      :error ->
        [Map.merge(rule_payload!(opts, payload_fun), %{only: [], except: []})]
    end
  end

  @spec rules!(term(), atom(), list(atom()), (keyword() -> map())) :: list(map())
  def rules!(rules, check, payload_keys, payload_fun) when is_list(rules) do
    if Enum.empty?(rules) or Enum.any?(rules, &(not Keyword.keyword?(&1))) do
      raise_rules_error!(check)
    end

    Enum.map(rules, &rule!(&1, check, payload_keys, payload_fun))
  end

  def rules!(_rules, check, _payload_keys, _payload_fun), do: raise_rules_error!(check)

  @spec matching_rules(Bylaw.Ecto.Query.Check.operation(), term(), list(map())) :: list(map())
  def matching_rules(operation, query, rules) do
    Enum.filter(rules, &in_rule_scope?(operation, query, &1))
  end

  @spec in_rule_scope?(Bylaw.Ecto.Query.Check.operation(), term(), rule()) :: boolean()
  def in_rule_scope?(operation, query, rule) do
    (Enum.empty?(rule.only) or matches_any?(operation, query, rule.only)) and
      not matches_any?(operation, query, rule.except)
  end

  defp rule!(rule, check, payload_keys, payload_fun) do
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
    |> rule_payload!(payload_fun)
    |> Map.merge(%{
      only: matchers(rule, scope_key(rule), check),
      except: matchers(rule, :except, check)
    })
  end

  defp rule_payload!(opts, payload_fun) do
    payload_fun.(opts)
  end

  defp validate_top_level_keys!(opts, _check, payload_keys) do
    allowed_keys = [:validate, :rules] ++ payload_keys

    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown option: #{inspect(key)}"
      end
    end)
  end

  defp reject_top_level_payload_keys_with_rules!(opts, check, payload_keys) do
    case Enum.find(payload_keys, &Keyword.has_key?(opts, &1)) do
      nil ->
        :ok

      key ->
        raise ArgumentError,
              "expected #{check} to use rule-level #{inspect(key)} when :rules is provided"
    end
  end

  defp scope_key(rule) do
    if Keyword.has_key?(rule, :only), do: :only, else: :where
  end

  defp matchers(opts, key, check) do
    case Keyword.fetch(opts, key) do
      {:ok, value} -> matchers!(value, check, key)
      :error -> []
    end
  end

  defp matchers!(value, check, key) when is_list(value) do
    cond do
      Keyword.keyword?(value) ->
        [matcher!(value, check, key)]

      Enum.empty?(value) ->
        raise_matchers_error!(check, key)

      Enum.all?(value, &Keyword.keyword?/1) ->
        Enum.map(value, &matcher!(&1, check, key))

      true ->
        raise_matchers_error!(check, key)
    end
  end

  defp matchers!(_value, check, key), do: raise_matchers_error!(check, key)

  defp matcher!(matcher, check, key) do
    if Enum.empty?(matcher) do
      raise_matchers_error!(check, key)
    end

    Enum.map(matcher, fn {matcher_key, matcher_value} ->
      if matcher_key not in @allowed_matcher_keys do
        raise ArgumentError,
              "unknown #{check} #{inspect(key)} matcher option: #{inspect(matcher_key)}"
      end

      matcher_values!(check, key, matcher_key, matcher_value)
      {matcher_key, matcher_value}
    end)
  end

  defp matcher_values!(check, key, matcher_key, values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not matcher_value?(matcher_key, &1))) do
      raise_matcher_values_error!(check, key, matcher_key)
    end
  end

  defp matcher_values!(check, key, matcher_key, value) do
    if not matcher_value?(matcher_key, value) do
      raise_matcher_values_error!(check, key, matcher_key)
    end
  end

  defp matcher_value?(:ecto_schema, value), do: ecto_schema?(value)
  defp matcher_value?(:operation, value), do: is_atom(value)
  defp matcher_value?(:table, %Regex{}), do: true
  defp matcher_value?(:table, value), do: non_empty_string?(value)
  defp matcher_value?(:db_schema, %Regex{}), do: true
  defp matcher_value?(:db_schema, value), do: non_empty_string?(value)

  defp ecto_schema?(value) when is_atom(value) and not is_nil(value) do
    function_exported?(value, :__schema__, 1)
  end

  defp ecto_schema?(_value), do: false

  defp matches_any?(_operation, _query, []), do: false

  defp matches_any?(operation, query, matchers) do
    Enum.any?(matchers, &matches?(operation, query, &1))
  end

  defp matches?(operation, query, matcher) do
    Enum.all?(matcher, fn {key, expected} ->
      operation
      |> value(query, key)
      |> matches_value?(expected)
    end)
  end

  defp value(operation, _query, :operation), do: operation

  defp value(_operation, query, :ecto_schema) do
    case Introspection.root_schema(query) do
      {:ok, schema} -> schema
      :unknown -> nil
    end
  end

  defp value(_operation, query, :table), do: Introspection.root_table(query)
  defp value(_operation, query, :db_schema), do: Introspection.root_prefix(query)

  defp matches_value?(nil, _expected), do: false

  defp matches_value?(value, expected) when is_list(expected) do
    Enum.any?(expected, &matches_value?(value, &1))
  end

  defp matches_value?(value, %Regex{} = regex) when is_binary(value),
    do: Regex.match?(regex, value)

  defp matches_value?(_value, %Regex{}), do: false
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
