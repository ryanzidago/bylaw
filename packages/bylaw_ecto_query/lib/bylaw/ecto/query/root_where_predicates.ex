defmodule Bylaw.Ecto.Query.RootWherePredicates do
  @moduledoc false

  alias Bylaw.Ecto.Query.Branches
  alias Bylaw.Ecto.Query.Introspection

  @type comparable_value :: atom() | integer() | String.t()
  @type operator :: :== | :in | :is_nil
  @type predicate :: %{
          field: atom(),
          operator: operator(),
          values: list(comparable_value())
        }

  @doc """
  Returns supported root `where` predicates grouped by boolean branch.

  Ordinary `where` clauses and `and` expressions merge predicate facts into the
  same branch. `or_where` clauses and `or` expressions produce alternate
  branches. Unsupported expressions contribute an empty branch.
  """
  @spec branches(term(), module()) :: list(list(predicate()))
  def branches(query, schema) when is_map(query) do
    root_aliases = Introspection.root_aliases(query)

    branches =
      query
      |> Map.get(:wheres, [])
      |> Enum.reduce(nil, fn where, branches ->
        where_branches = predicate_branches_in_where(where, schema, root_aliases)

        case Map.get(where, :op, :and) do
          :or -> Branches.concat(branches, where_branches)
          _op -> Branches.merge(branches, where_branches, &append_predicate_branches/2)
        end
      end)

    case branches do
      nil -> [[]]
      branches -> branches
    end
  end

  def branches(_query, _schema), do: [[]]

  defp predicate_branches_in_where(%{expr: expr, params: params}, schema, root_aliases) do
    predicate_branches_in_expr(expr, params, schema, root_aliases)
  end

  defp predicate_branches_in_where(_where, _schema, _root_aliases), do: [[]]

  defp predicate_branches_in_expr({:and, _meta, [left, right]}, params, schema, root_aliases) do
    left_branches = predicate_branches_in_expr(left, params, schema, root_aliases)
    right_branches = predicate_branches_in_expr(right, params, schema, root_aliases)

    Branches.merge(left_branches, right_branches, &append_predicate_branches/2)
  end

  defp predicate_branches_in_expr({:or, _meta, [left, right]}, params, schema, root_aliases) do
    predicate_branches_in_expr(left, params, schema, root_aliases) ++
      predicate_branches_in_expr(right, params, schema, root_aliases)
  end

  defp predicate_branches_in_expr({:==, _meta, [left, right]}, params, schema, root_aliases) do
    [equality_predicates(left, right, params, schema, root_aliases)]
  end

  defp predicate_branches_in_expr({:in, _meta, [left, right]}, params, schema, root_aliases) do
    [in_predicates(left, right, params, schema, root_aliases)]
  end

  defp predicate_branches_in_expr({:is_nil, _meta, [expr]}, _params, schema, root_aliases) do
    [nil_predicates(expr, schema, root_aliases)]
  end

  defp predicate_branches_in_expr(_expr, _params, _schema, _root_aliases), do: [[]]

  defp append_predicate_branches(left_branch, right_branch), do: left_branch ++ right_branch

  defp equality_predicates(left, right, params, schema, root_aliases) do
    case field_predicate(left, right, :==, params, schema, root_aliases) do
      {:ok, predicate} ->
        [predicate]

      :error ->
        case field_predicate(right, left, :==, params, schema, root_aliases) do
          {:ok, predicate} -> [predicate]
          :error -> []
        end
    end
  end

  defp in_predicates(left, right, params, schema, root_aliases) do
    case Introspection.root_field(left, root_aliases) do
      {:ok, field} ->
        case comparable_values(schema, field, right, params) do
          {:ok, values} -> [%{field: field, operator: :in, values: values}]
          :error -> []
        end

      :unknown ->
        []
    end
  end

  defp nil_predicates(expr, schema, root_aliases) do
    with {:ok, field} <- Introspection.root_field(expr, root_aliases),
         true <- Introspection.schema_field?(schema, field) do
      [%{field: field, operator: :is_nil, values: [nil]}]
    else
      _other -> []
    end
  end

  defp field_predicate(field_expr, value_expr, operator, params, schema, root_aliases) do
    with {:ok, field} <- Introspection.root_field(field_expr, root_aliases),
         {:ok, value} <- comparable_value(schema, field, value_expr, params) do
      {:ok, %{field: field, operator: operator, values: [value]}}
    else
      _other -> :error
    end
  end

  defp comparable_value(schema, field, expr, params) do
    with true <- Introspection.schema_field?(schema, field),
         {:ok, value} <- value(expr, params) do
      normalize_comparable_value(schema, field, value)
    else
      _other -> :error
    end
  end

  defp comparable_values(schema, field, expr, params) do
    with true <- Introspection.schema_field?(schema, field),
         {:ok, values} <- values(expr, params) do
      normalize_comparable_values(schema, field, values)
    else
      _other -> :error
    end
  end

  defp enum_field?(schema, field) do
    schema
    |> schema_type(field)
    |> Ecto.Type.parameterized?(Ecto.Enum)
  end

  defp schema_type(schema, field), do: schema.__schema__(:type, field)

  defp normalize_comparable_value(schema, field, value) do
    cond do
      enum_field?(schema, field) ->
        cast_enum_value(schema, field, value)

      comparable_value_for_type?(schema_type(schema, field), value) ->
        {:ok, value}

      true ->
        :error
    end
  end

  defp cast_enum_value(schema, field, value) do
    case Ecto.Enum.cast_value(schema, field, value) do
      {:ok, enum_value} -> {:ok, enum_value}
      :error -> :error
    end
  end

  defp normalize_comparable_values(schema, field, values) do
    values = Enum.reject(values, &is_nil/1)

    if Enum.empty?(values) do
      {:ok, []}
    else
      do_normalize_comparable_values(schema, field, values)
    end
  end

  defp do_normalize_comparable_values(schema, field, values) do
    comparable_values =
      Enum.reduce_while(values, [], fn value, acc ->
        case normalize_comparable_value(schema, field, value) do
          {:ok, comparable_value} -> {:cont, [comparable_value | acc]}
          :error -> {:halt, :error}
        end
      end)

    case comparable_values do
      :error -> :error
      comparable_values -> {:ok, dedupe_comparable_values(comparable_values)}
    end
  end

  defp dedupe_comparable_values(values) do
    values
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp comparable_value_for_type?(type, value) when type in [:id, :integer], do: is_integer(value)

  defp comparable_value_for_type?(type, value) when type in [:string, :binary, :binary_id],
    do: is_binary(value)

  defp comparable_value_for_type?(:boolean, value), do: is_boolean(value)
  defp comparable_value_for_type?(_type, _value), do: false

  defp value(%Ecto.Query.Tagged{value: value}, _params), do: {:ok, value}

  defp value({:^, _meta, [index]}, params) when is_integer(index) do
    case Enum.fetch(params, index) do
      {:ok, {value, _type}} -> {:ok, value}
      :error -> :error
    end
  end

  defp value(value, _params)
       when is_atom(value) or is_binary(value) or is_integer(value) do
    {:ok, value}
  end

  defp value(_expr, _params), do: :error

  defp values(%Ecto.Query.Tagged{value: values}, _params) when is_list(values), do: {:ok, values}

  defp values({:^, _meta, [index]} = expr, params) when is_integer(index) do
    case value(expr, params) do
      {:ok, values} when is_list(values) -> {:ok, values}
      _other -> :error
    end
  end

  defp values(values, params) when is_list(values) do
    parsed_values =
      Enum.reduce_while(values, [], fn expr, acc ->
        case value(expr, params) do
          {:ok, value} -> {:cont, [value | acc]}
          :error -> {:halt, :error}
        end
      end)

    case parsed_values do
      :error -> :error
      values -> {:ok, Enum.reverse(values)}
    end
  end

  defp values(_expr, _params), do: :error
end
