defmodule Bylaw.Contract.TypeMatcher do
  @moduledoc false

  @type result :: :match | :no_match | :unknown

  @spec match(value :: term(), type :: term()) :: result()
  def match(value, type), do: do_match(value, type, %{})

  @spec supported?(type :: term()) :: boolean()
  def supported?(type), do: do_supported?(type, %{})

  defp do_supported?({:bylaw_contract, :type_graph, root, nodes}, _definitions),
    do: do_supported?(root, nodes)

  defp do_supported?({:bylaw_contract, :type_ref, id}, definitions) do
    {_body, supported?} = Map.fetch!(definitions, id)
    supported?
  end

  defp do_supported?({:unsupported, _}, _definitions), do: false
  defp do_supported?({:ann_type, _, [_, type]}, definitions), do: do_supported?(type, definitions)

  defp do_supported?({:bylaw_contract, :binary_size, size}, _definitions)
       when size in [:empty, :nonempty], do: true

  defp do_supported?({:bylaw_contract, :list_length, length, element_type}, definitions)
       when length in [:empty, :singleton, :multiple],
       do: do_supported?(element_type, definitions)

  defp do_supported?({kind, _, _}, _definitions)
       when kind in [:atom, :integer, :char, :float, :string],
       do: true

  defp do_supported?({:var, _, _}, _definitions), do: true

  defp do_supported?({:type, _, :union, members}, definitions),
    do: Enum.all?(members, &do_supported?(&1, definitions))

  defp do_supported?({:type, _, type, []}, _definitions)
       when type in [
              :any,
              :term,
              :atom,
              :boolean,
              :integer,
              :non_neg_integer,
              :pos_integer,
              :neg_integer,
              :float,
              :number,
              :binary,
              :nonempty_binary,
              :bitstring,
              :nonempty_bitstring,
              :byte,
              :char,
              :pid,
              :port,
              :reference,
              :identifier,
              :module,
              :node,
              :arity,
              :timeout,
              :mfa,
              :struct,
              :charlist,
              :nonempty_charlist,
              :string,
              :nonempty_string,
              :iolist,
              :iodata,
              :tuple,
              :map,
              nil,
              :list,
              :fun,
              :function,
              :none,
              :no_return
            ],
       do: true

  defp do_supported?({:type, _, type, :any}, _definitions) when type in [:tuple, :map], do: true

  defp do_supported?({:type, _, :tuple, elements}, definitions),
    do: Enum.all?(elements, &do_supported?(&1, definitions))

  defp do_supported?({:type, _, :map, fields}, definitions) do
    Enum.all?(fields, fn
      {:type, _, field_kind, [key_type, value_type]}
      when field_kind in [:map_field_exact, :map_field_assoc] ->
        do_supported?(key_type, definitions) and do_supported?(value_type, definitions)

      _ ->
        false
    end)
  end

  defp do_supported?({:type, _, type, [element_type]}, definitions)
       when type in [:list, :nonempty_list],
       do: do_supported?(element_type, definitions)

  defp do_supported?({:type, _, :range, [{:integer, _, _}, {:integer, _, _}]}, _definitions),
    do: true

  defp do_supported?({:type, _, :fun, [{:type, _, :product, arguments}, _]}, _definitions),
    do: is_list(arguments)

  defp do_supported?(_, _definitions), do: false

  defp do_match(value, {:bylaw_contract, :type_graph, root, nodes}, _definitions),
    do: do_match(value, root, nodes)

  defp do_match(value, {:bylaw_contract, :type_ref, id}, definitions) do
    {body, _supported?} = Map.fetch!(definitions, id)
    do_match(value, body, definitions)
  end

  defp do_match(_, {:unsupported, _}, _definitions), do: :unknown

  defp do_match(value, {:ann_type, _, [_, type]}, definitions),
    do: do_match(value, type, definitions)

  defp do_match(_, {:var, _, _}, _definitions), do: :match

  defp do_match(value, {:bylaw_contract, :binary_size, :empty}, _definitions),
    do: yes(is_binary(value) and byte_size(value) == 0)

  defp do_match(value, {:bylaw_contract, :binary_size, :nonempty}, _definitions),
    do: yes(is_binary(value) and byte_size(value) > 0)

  defp do_match(value, {:bylaw_contract, :list_length, length, element_type}, definitions) do
    if is_list(value) and list_length?(value, length) do
      match_list(value, element_type, definitions)
    else
      :no_match
    end
  end

  defp do_match(value, {:atom, _, literal}, _definitions), do: yes(value === literal)
  defp do_match(value, {:integer, _, literal}, _definitions), do: yes(value === literal)
  defp do_match(value, {:char, _, literal}, _definitions), do: yes(value === literal)
  defp do_match(value, {:float, _, literal}, _definitions), do: yes(value === literal)
  defp do_match(value, {:string, _, literal}, _definitions), do: yes(value === literal)

  defp do_match(value, {:type, _, :union, members}, definitions) do
    members
    |> Enum.map(&do_match(value, &1, definitions))
    |> any_result()
  end

  defp do_match(_, {:type, _, type, []}, _definitions) when type in [:any, :term], do: :match
  defp do_match(value, {:type, _, :atom, []}, _definitions), do: yes(is_atom(value))
  defp do_match(value, {:type, _, :boolean, []}, _definitions), do: yes(is_boolean(value))
  defp do_match(value, {:type, _, :integer, []}, _definitions), do: yes(is_integer(value))

  defp do_match(value, {:type, _, :non_neg_integer, []}, _definitions),
    do: yes(is_integer(value) and value >= 0)

  defp do_match(value, {:type, _, :pos_integer, []}, _definitions),
    do: yes(is_integer(value) and value > 0)

  defp do_match(value, {:type, _, :neg_integer, []}, _definitions),
    do: yes(is_integer(value) and value < 0)

  defp do_match(value, {:type, _, :float, []}, _definitions), do: yes(is_float(value))
  defp do_match(value, {:type, _, :number, []}, _definitions), do: yes(is_number(value))
  defp do_match(value, {:type, _, :binary, []}, _definitions), do: yes(is_binary(value))

  defp do_match(value, {:type, _, :nonempty_binary, []}, _definitions),
    do: yes(is_binary(value) and byte_size(value) > 0)

  defp do_match(value, {:type, _, :bitstring, []}, _definitions), do: yes(is_bitstring(value))

  defp do_match(value, {:type, _, :nonempty_bitstring, []}, _definitions),
    do: yes(is_bitstring(value) and bit_size(value) > 0)

  defp do_match(value, {:type, _, :byte, []}, _definitions),
    do: yes(is_integer(value) and value in 0..255)

  defp do_match(value, {:type, _, :char, []}, _definitions),
    do: yes(is_integer(value) and value >= 0 and value <= 0x10FFFF)

  defp do_match(value, {:type, _, :pid, []}, _definitions), do: yes(is_pid(value))
  defp do_match(value, {:type, _, :port, []}, _definitions), do: yes(is_port(value))
  defp do_match(value, {:type, _, :reference, []}, _definitions), do: yes(is_reference(value))

  defp do_match(value, {:type, _, :identifier, []}, _definitions),
    do: yes(is_pid(value) or is_port(value) or is_reference(value))

  defp do_match(value, {:type, _, :module, []}, _definitions), do: yes(is_atom(value))
  defp do_match(value, {:type, _, :node, []}, _definitions), do: yes(is_atom(value))

  defp do_match(value, {:type, _, :arity, []}, _definitions),
    do: yes(is_integer(value) and value in 0..255)

  defp do_match(value, {:type, _, :timeout, []}, _definitions),
    do: yes(value == :infinity or (is_integer(value) and value >= 0))

  defp do_match({module, function, arity}, {:type, _, :mfa, []}, _definitions),
    do: yes(is_atom(module) and is_atom(function) and is_integer(arity) and arity in 0..255)

  defp do_match(_, {:type, _, :mfa, []}, _definitions), do: :no_match

  defp do_match(value, {:type, _, :struct, []}, _definitions),
    do: yes(is_map(value) and is_atom(Map.get(value, :__struct__)))

  defp do_match(value, {:type, _, type, []}, _definitions) when type in [:charlist, :string],
    do: yes(charlist?(value))

  defp do_match(value, {:type, _, type, []}, _definitions)
       when type in [:nonempty_charlist, :nonempty_string],
       do: yes(charlist?(value) and not Enum.empty?(value))

  defp do_match(value, {:type, _, :iolist, []}, _definitions),
    do: yes(is_list(value) and iodata?(value))

  defp do_match(value, {:type, _, :iodata, []}, _definitions), do: yes(iodata?(value))

  defp do_match(value, {:type, _, :tuple, :any}, _definitions), do: yes(is_tuple(value))
  defp do_match(value, {:type, _, :tuple, []}, _definitions), do: yes(is_tuple(value))

  defp do_match(value, {:type, _, :tuple, elements}, definitions) when is_list(elements) do
    if is_tuple(value) and tuple_size(value) == Enum.count(elements) do
      value
      |> Tuple.to_list()
      |> Enum.zip(elements)
      |> Enum.map(fn {element, type} -> do_match(element, type, definitions) end)
      |> all_result()
    else
      :no_match
    end
  end

  defp do_match(value, {:type, _, :map, :any}, _definitions), do: yes(is_map(value))
  defp do_match(value, {:type, _, :map, []}, _definitions), do: yes(is_map(value))

  defp do_match(value, {:type, _, :map, fields}, definitions) when is_list(fields) do
    if is_map(value) do
      fields
      |> Enum.map(&match_map_field(value, &1, definitions))
      |> all_result()
    else
      :no_match
    end
  end

  defp do_match([], {:type, _, nil, []}, _definitions), do: :match
  defp do_match(_, {:type, _, nil, []}, _definitions), do: :no_match
  defp do_match(value, {:type, _, :list, []}, _definitions), do: yes(is_list(value))

  defp do_match(value, {:type, _, :list, [element_type]}, definitions) do
    if is_list(value) do
      match_list(value, element_type, definitions)
    else
      :no_match
    end
  end

  defp do_match(value, {:type, _, :nonempty_list, [element_type]}, definitions) do
    if is_list(value) and Enum.any?(value) do
      match_list(value, element_type, definitions)
    else
      :no_match
    end
  end

  defp do_match(value, {:type, _, :range, [first, last]}, _definitions) do
    with {:integer, _, first} <- first,
         {:integer, _, last} <- last do
      yes(is_integer(value) and value >= first and value <= last)
    else
      _ -> :unknown
    end
  end

  defp do_match(value, {:type, _, :fun, []}, _definitions), do: yes(is_function(value))
  defp do_match(value, {:type, _, :function, []}, _definitions), do: yes(is_function(value))

  defp do_match(value, {:type, _, :fun, [{:type, _, :product, arguments}, _]}, _definitions) do
    yes(is_function(value, Enum.count(arguments)))
  end

  defp do_match(_, {:type, _, type, []}, _definitions) when type in [:none, :no_return],
    do: :no_match

  defp do_match(_, _, _definitions), do: :unknown

  defp match_list(list, element_type, definitions) do
    list
    |> Enum.map(&do_match(&1, element_type, definitions))
    |> all_result()
  end

  defp match_map_field(map, {:type, _, :map_field_exact, [key_type, value_type]}, definitions) do
    case literal(key_type, definitions) do
      {:ok, key} ->
        if Map.has_key?(map, key) do
          do_match(Map.fetch!(map, key), value_type, definitions)
        else
          :no_match
        end

      :error ->
        match_typed_map_entries(map, key_type, value_type, true, definitions)
    end
  end

  defp match_map_field(map, {:type, _, :map_field_assoc, [key_type, value_type]}, definitions),
    do: match_typed_map_entries(map, key_type, value_type, false, definitions)

  defp match_map_field(_, _, _definitions), do: :unknown

  defp match_typed_map_entries(map, key_type, value_type, required?, definitions) do
    matching_values =
      for {key, value} <- Map.to_list(map),
          do_match(key, key_type, definitions) == :match,
          do: value

    if required? and Enum.empty?(matching_values) do
      :no_match
    else
      matching_values
      |> Enum.map(&do_match(&1, value_type, definitions))
      |> all_result()
    end
  end

  defp literal({:bylaw_contract, :type_ref, id}, definitions) do
    {body, _supported?} = Map.fetch!(definitions, id)
    literal(body, definitions)
  end

  defp literal({:atom, _, value}, _definitions), do: {:ok, value}
  defp literal({:integer, _, value}, _definitions), do: {:ok, value}
  defp literal({:char, _, value}, _definitions), do: {:ok, value}
  defp literal({:float, _, value}, _definitions), do: {:ok, value}
  defp literal({:string, _, value}, _definitions), do: {:ok, value}
  defp literal(_, _definitions), do: :error

  defp all_result(results) do
    cond do
      Enum.any?(results, &(&1 == :no_match)) -> :no_match
      Enum.any?(results, &(&1 == :unknown)) -> :unknown
      true -> :match
    end
  end

  defp any_result(results) do
    cond do
      Enum.any?(results, &(&1 == :match)) -> :match
      Enum.any?(results, &(&1 == :unknown)) -> :unknown
      true -> :no_match
    end
  end

  defp yes(true), do: :match
  defp yes(false), do: :no_match

  defp list_length?([], :empty), do: true
  defp list_length?([_], :singleton), do: true
  defp list_length?([_, _ | _], :multiple), do: true
  defp list_length?(_, _), do: false

  defp charlist?(value) when is_list(value) do
    Enum.all?(value, &(is_integer(&1) and &1 >= 0 and &1 <= 0x10FFFF))
  end

  defp charlist?(_), do: false

  defp iodata?(value) do
    :erlang.iolist_size(value)
    true
  rescue
    ArgumentError -> false
  end
end
