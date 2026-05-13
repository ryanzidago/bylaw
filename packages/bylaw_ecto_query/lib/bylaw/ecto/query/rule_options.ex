defmodule Bylaw.Ecto.Query.RuleOptions do
  @moduledoc false

  alias Bylaw.Ecto.Query.Introspection

  @type matcher_value :: module() | atom() | String.t() | Regex.t()
  @type matcher_values :: list(matcher_value())
  @type matcher :: keyword(matcher_values())
  @type rule :: %{opts: keyword(), where: list(matcher()), except: list(matcher())}

  @matcher_keys %{
    ecto_schemas: :ecto_schema,
    tables: :table,
    db_schemas: :db_schema,
    operations: :operation
  }
  @allowed_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  @spec fetch_rules!(keyword(), atom(), list(atom())) :: list(rule())
  def fetch_rules!(opts, check, rule_option_keys) do
    case Keyword.fetch(opts, :rules) do
      {:ok, rules} -> rules!(rules, check, rule_option_keys)
      :error -> raise ArgumentError, "missing required :rules option"
    end
  end

  @spec rules_or_default!(keyword(), atom(), list(atom())) :: list(rule())
  def rules_or_default!(opts, check, rule_option_keys) do
    case Keyword.fetch(opts, :rules) do
      {:ok, rules} -> rules!(rules, check, rule_option_keys)
      :error -> [rule!(Keyword.delete(opts, :rules), check, rule_option_keys)]
    end
  end

  @spec scope_rules_or_default!(keyword(), atom()) :: list(rule())
  def scope_rules_or_default!(opts, check), do: rules_or_default!(opts, check, [])

  @spec scoped?(keyword(), atom(), Bylaw.Ecto.Query.Check.operation(), term()) :: boolean()
  def scoped?(opts, check, operation, query) do
    rules = scope_rules_or_default!(opts, check)
    matching_rules = matching_rules(operation, query, rules)

    not Enum.empty?(matching_rules)
  end

  @spec rules!(term(), atom(), list(atom())) :: list(rule())
  def rules!(rules, check, rule_option_keys) when is_list(rules) do
    cond do
      Enum.empty?(rules) ->
        raise_rules_error!(check)

      Keyword.keyword?(rules) ->
        [rule!(rules, check, rule_option_keys)]

      Enum.all?(rules, &Keyword.keyword?/1) ->
        Enum.map(rules, &rule!(&1, check, rule_option_keys))

      true ->
        raise_rules_error!(check)
    end
  end

  def rules!(_rules, check, _rule_option_keys), do: raise_rules_error!(check)

  @spec matching_rules(Bylaw.Ecto.Query.Check.operation(), term(), list(map())) :: list(map())
  def matching_rules(operation, query, rules) do
    effective_query = Introspection.effective_root_query(query)

    Enum.filter(rules, fn rule ->
      rule_enabled?(rule) and in_rule_scope?(operation, effective_query, rule)
    end)
  end

  @spec matching_rules(Bylaw.Ecto.Query.Check.operation(), term(), list(map()), (keyword() ->
                                                                                   map())) ::
          list(map())
  def matching_rules(operation, query, rules, rule_options_fun) do
    operation
    |> matching_rules(query, rules)
    |> Enum.map(fn rule -> Map.merge(rule, rule_options_fun.(rule.opts)) end)
  end

  @spec in_rule_scope?(Bylaw.Ecto.Query.Check.operation(), term(), rule()) :: boolean()
  def in_rule_scope?(operation, query, rule) do
    (Enum.empty?(rule.where) or matches_any?(operation, query, rule.where)) and
      not matches_any?(operation, query, rule.except)
  end

  defp rule!(rule, check, rule_option_keys) do
    allowed_rule_keys = [:where, :except, :validate] ++ rule_option_keys

    Enum.each(rule, fn {key, _value} ->
      if key not in allowed_rule_keys do
        raise ArgumentError, "unknown #{check} rule option: #{inspect(key)}"
      end
    end)

    %{
      opts: rule,
      where: matchers(rule, :where, check),
      except: matchers(rule, :except, check)
    }
  end

  defp rule_enabled?(rule), do: Keyword.get(rule.opts, :validate, true) != false

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
      case Map.fetch(@matcher_keys, matcher_key) do
        {:ok, normalized_key} ->
          matcher_values!(check, key, matcher_key, normalized_key, matcher_value)
          {normalized_key, matcher_value}

        :error ->
          raise ArgumentError,
                "unknown #{check} #{inspect(key)} matcher option: #{inspect(matcher_key)}"
      end
    end)
  end

  defp matcher_values!(check, key, matcher_key, normalized_key, values) when is_list(values) do
    if Enum.empty?(values) or Enum.any?(values, &(not matcher_value?(normalized_key, &1))) do
      raise_matcher_values_error!(check, key, matcher_key)
    end
  end

  defp matcher_values!(check, key, matcher_key, _normalized_key, _value) do
    raise_matcher_values_error!(check, key, matcher_key)
  end

  defp matcher_value?(:ecto_schema, value), do: ecto_schema?(value)
  defp matcher_value?(:operation, value), do: value in @allowed_operations
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
    raise ArgumentError,
          "expected #{check} :rules to be a keyword rule or non-empty list of keyword rules"
  end

  defp raise_matchers_error!(check, key) do
    raise ArgumentError,
          "expected #{check} #{inspect(key)} to be a matcher or non-empty list of matchers"
  end

  defp raise_matcher_values_error!(check, key, matcher_key) do
    raise ArgumentError,
          "expected #{check} #{inspect(key)} #{inspect(matcher_key)} to be a non-empty list of matcher values"
  end

  defp non_empty_string?(value), do: is_binary(value) and byte_size(value) > 0
end
