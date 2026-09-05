defmodule Bylaw.Contract.CompilerTypeMatcher do
  @moduledoc false

  @type result :: :match | :no_match | :unknown

  @doc false
  @spec supported?(type :: term()) :: boolean()
  def supported?({:dynamic, _, [type]}), do: supported?(type)

  def supported?({operator, _, [left, right]}) when operator in [:or, :and],
    do: supported?(left) and supported?(right)

  def supported?({:not, _, [type]}), do: supported?(type)

  def supported?({:__block__, _, [arrows]}) when is_list(arrows),
    do: match?({:ok, _}, function_arities(arrows))

  def supported?({:__block__, _, [literal]}), do: literal?(literal)
  def supported?({:__aliases__, _, parts}), do: match?({:ok, _}, module_literal(parts))

  def supported?({:%, _, [module_type, {:%{}, _, fields}]}) when is_list(fields),
    do: supported?(module_type) and map_fields_supported?(fields)

  def supported?({:%{}, _, fields}) when is_list(fields), do: map_fields_supported?(fields)

  def supported?({:{}, _, elements}) when is_list(elements),
    do: Enum.all?(elements, &supported?/1)

  def supported?({type, _, []})
      when type in [
             :none,
             :term,
             :atom,
             :boolean,
             :binary,
             :bitstring,
             :integer,
             :float,
             :pid,
             :port,
             :reference,
             :tuple,
             :map,
             :empty_list,
             :empty_map,
             :non_struct_map,
             :fun
           ],
      do: true

  def supported?({:non_empty_list, _, [element_type]}), do: supported?(element_type)

  def supported?({:list, _, [element_type]}), do: supported?(element_type)

  def supported?({:non_empty_list, _, [element_type, tail_type]}),
    do: supported?(element_type) and supported?(tail_type)

  def supported?(_), do: false

  @doc false
  @spec match(value :: term(), type :: term()) :: result()
  def match(value, {:dynamic, _, [type]}), do: match(value, type)

  def match(value, {:or, _, [left, right]}) do
    combine_or(match(value, left), match(value, right))
  end

  def match(value, {:and, _, [left, right]}) do
    combine_and(match(value, left), match(value, right))
  end

  def match(value, {:not, _, [type]}) do
    case match(value, type) do
      :match -> :no_match
      :no_match -> :match
      :unknown -> :unknown
    end
  end

  def match(value, {:__block__, _, [arrows]}) when is_list(arrows) do
    case function_arities(arrows) do
      {:ok, arities} -> yes(Enum.any?(arities, &:erlang.is_function(value, &1)))
      :error -> :unknown
    end
  end

  def match(value, {:__block__, _, [literal]}) do
    if literal?(literal) do
      yes(value === literal)
    else
      :unknown
    end
  end

  def match(value, {:__aliases__, _, parts}) do
    case module_literal(parts) do
      {:ok, module} -> yes(value === module)
      :error -> :unknown
    end
  end

  def match(value, {:%, _, [module_type, {:%{}, _, fields}]}) when is_list(fields) do
    with {:match, _module} <- match_module(value, module_type),
         :match <- match_map_fields(value, fields, :open) do
      :match
    else
      {:no_match, _} -> :no_match
      :no_match -> :no_match
      _ -> :unknown
    end
  end

  def match(value, {:%{}, _, fields}) when is_list(fields) do
    if is_map(value) do
      openness =
        if Enum.any?(fields, &match?({:..., _, _}, &1)) do
          :open
        else
          :closed
        end

      match_map_fields(value, fields, openness)
    else
      :no_match
    end
  end

  def match(value, {:{}, _, elements}) when is_tuple(value) and is_list(elements) do
    if tuple_size(value) == Enum.count(elements) do
      value
      |> Tuple.to_list()
      |> Enum.zip(elements)
      |> match_pairs()
    else
      :no_match
    end
  end

  def match(_, {:{}, _, elements}) when is_list(elements), do: :no_match
  def match(_, {:none, _, []}), do: :no_match
  def match(_, {:term, _, []}), do: :match
  def match(value, {:atom, _, []}), do: yes(is_atom(value))
  def match(value, {:boolean, _, []}), do: yes(is_boolean(value))
  def match(value, {:binary, _, []}), do: yes(is_binary(value))
  def match(value, {:bitstring, _, []}), do: yes(is_bitstring(value))
  def match(value, {:integer, _, []}), do: yes(is_integer(value))
  def match(value, {:float, _, []}), do: yes(is_float(value))
  def match(value, {:pid, _, []}), do: yes(is_pid(value))
  def match(value, {:port, _, []}), do: yes(is_port(value))
  def match(value, {:reference, _, []}), do: yes(is_reference(value))
  def match(value, {:tuple, _, []}), do: yes(is_tuple(value))
  def match(value, {:map, _, []}), do: yes(is_map(value))
  def match(value, {:empty_map, _, []}), do: yes(is_map(value) and map_size(value) == 0)

  def match(value, {:non_struct_map, _, []}),
    do: yes(is_map(value) and not Map.has_key?(value, :__struct__))

  def match(value, {:fun, _, []}), do: yes(is_function(value))

  def match([], {:empty_list, _, []}), do: :match
  def match(_, {:empty_list, _, []}), do: :no_match

  def match(value, {:list, _, [element_type]}), do: match_proper_list(value, element_type)

  def match([_ | _] = value, {:non_empty_list, _, [element_type]}) do
    match_proper_list(value, element_type)
  end

  def match(_, {:non_empty_list, _, [_]}), do: :no_match

  def match([_ | _] = value, {:non_empty_list, _, [element_type, tail_type]}) do
    match_list(value, element_type, tail_type)
  end

  def match(_, {:non_empty_list, _, [_, _]}), do: :no_match
  def match(_, _), do: :unknown

  defp literal?(literal),
    do: is_atom(literal) or is_integer(literal) or is_float(literal) or is_binary(literal)

  defp map_fields_supported?(fields) do
    Enum.all?(fields, fn
      {:..., _, _} -> true
      {key, value_type} -> match?({:ok, _}, quoted_literal(key)) and supported?(value_type)
      _ -> false
    end)
  end

  defp match_module(value, {:__aliases__, _, parts}) do
    case module_literal(parts) do
      {:ok, module} -> {yes(is_map(value) and Map.get(value, :__struct__) === module), module}
      :error -> {:unknown, nil}
    end
  end

  defp match_module(_value, _module_type), do: {:unknown, nil}

  defp match_map_fields(map, fields, openness) do
    if openness == :closed and map_size(map) != Enum.count(fields) do
      :no_match
    else
      Enum.reduce_while(fields, :match, fn
        {:..., _, _}, :match ->
          {:cont, :match}

        {key_type, value_type}, :match ->
          case quoted_literal(key_type) do
            {:ok, key} when is_map_key(map, key) ->
              case match(Map.fetch!(map, key), value_type) do
                :match -> {:cont, :match}
                result -> {:halt, result}
              end

            {:ok, _key} ->
              {:halt, :no_match}

            :error ->
              {:halt, :unknown}
          end

        _, :match ->
          {:halt, :unknown}
      end)
    end
  end

  defp quoted_literal({:__block__, _, [literal]}) do
    if literal?(literal) do
      {:ok, literal}
    else
      :error
    end
  end

  defp quoted_literal(_), do: :error

  defp module_literal(parts) when is_list(parts) do
    if Enum.all?(parts, &is_atom/1) do
      if Enum.any?(parts) do
        {:ok, Module.safe_concat(parts)}
      else
        :error
      end
    else
      :error
    end
  rescue
    ArgumentError -> :error
  end

  defp module_literal(_parts), do: :error

  defp function_arities(arrows) do
    Enum.reduce_while(arrows, {:ok, []}, fn
      {:->, _, [arguments, _return_type]}, {:ok, arities} when is_list(arguments) ->
        {:cont, {:ok, [Enum.count(arguments) | arities]}}

      _, _ ->
        {:halt, :error}
    end)
  end

  defp match_pairs(pairs) do
    Enum.reduce_while(pairs, :match, fn {value, type}, _ ->
      case match(value, type) do
        :match -> {:cont, :match}
        result -> {:halt, result}
      end
    end)
  end

  defp match_proper_list([], _element_type), do: :match

  defp match_proper_list([head | tail], element_type) do
    case match(head, element_type) do
      :match -> match_proper_list(tail, element_type)
      result -> result
    end
  end

  defp match_proper_list(_tail, _element_type), do: :no_match

  defp match_list([head | tail], element_type, tail_type) do
    case match(head, element_type) do
      :match -> match_list_tail(tail, element_type, tail_type)
      result -> result
    end
  end

  defp match_list_tail([_ | _] = tail, element_type, tail_type),
    do: match_list(tail, element_type, tail_type)

  defp match_list_tail(tail, _element_type, tail_type), do: match(tail, tail_type)

  defp combine_or(:match, _), do: :match
  defp combine_or(_, :match), do: :match
  defp combine_or(:unknown, _), do: :unknown
  defp combine_or(_, :unknown), do: :unknown
  defp combine_or(:no_match, :no_match), do: :no_match

  defp combine_and(:no_match, _), do: :no_match
  defp combine_and(_, :no_match), do: :no_match
  defp combine_and(:unknown, _), do: :unknown
  defp combine_and(_, :unknown), do: :unknown
  defp combine_and(:match, :match), do: :match

  defp yes(true), do: :match
  defp yes(false), do: :no_match
end
