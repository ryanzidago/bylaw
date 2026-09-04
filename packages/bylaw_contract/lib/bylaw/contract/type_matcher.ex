defmodule Bylaw.Contract.TypeMatcher do
  @moduledoc false

  @type result :: :match | :no_match | :unknown

  @spec match(value :: term(), type :: term()) :: result()
  def match(value, type), do: do_match(value, type)

  @spec supported?(type :: term()) :: boolean()
  def supported?({:unsupported, _}), do: false
  def supported?({:ann_type, _, [_, type]}), do: supported?(type)
  def supported?({:bylaw_contract, :binary_size, size}) when size in [:empty, :nonempty], do: true

  def supported?({:bylaw_contract, :list_length, length, element_type})
      when length in [:empty, :singleton, :multiple],
      do: supported?(element_type)

  def supported?({kind, _, _}) when kind in [:atom, :integer, :char, :float, :string],
    do: true

  def supported?({:var, _, _}), do: true
  def supported?({:type, _, :union, members}), do: Enum.all?(members, &supported?/1)

  def supported?({:type, _, type, []})
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

  def supported?({:type, _, type, :any}) when type in [:tuple, :map], do: true
  def supported?({:type, _, :tuple, elements}), do: Enum.all?(elements, &supported?/1)

  def supported?({:type, _, :map, fields}) do
    Enum.all?(fields, fn
      {:type, _, field_kind, [key_type, value_type]}
      when field_kind in [:map_field_exact, :map_field_assoc] ->
        supported?(key_type) and supported?(value_type)

      _ ->
        false
    end)
  end

  def supported?({:type, _, type, [element_type]}) when type in [:list, :nonempty_list],
    do: supported?(element_type)

  def supported?({:type, _, :range, [{:integer, _, _}, {:integer, _, _}]}), do: true

  def supported?({:type, _, :fun, [{:type, _, :product, arguments}, _]}),
    do: is_list(arguments)

  def supported?(_), do: false

  defp do_match(_, {:unsupported, _}), do: :unknown
  defp do_match(value, {:ann_type, _, [_, type]}), do: do_match(value, type)
  defp do_match(_, {:var, _, _}), do: :match

  defp do_match(value, {:bylaw_contract, :binary_size, :empty}),
    do: yes(is_binary(value) and byte_size(value) == 0)

  defp do_match(value, {:bylaw_contract, :binary_size, :nonempty}),
    do: yes(is_binary(value) and byte_size(value) > 0)

  defp do_match(value, {:bylaw_contract, :list_length, length, element_type}) do
    if is_list(value) and list_length?(value, length) do
      match_list(value, element_type)
    else
      :no_match
    end
  end

  defp do_match(value, {:atom, _, literal}), do: yes(value === literal)
  defp do_match(value, {:integer, _, literal}), do: yes(value === literal)
  defp do_match(value, {:char, _, literal}), do: yes(value === literal)
  defp do_match(value, {:float, _, literal}), do: yes(value === literal)
  defp do_match(value, {:string, _, literal}), do: yes(value === literal)

  defp do_match(value, {:type, _, :union, members}) do
    members
    |> Enum.map(&do_match(value, &1))
    |> any_result()
  end

  defp do_match(_, {:type, _, type, []}) when type in [:any, :term], do: :match
  defp do_match(value, {:type, _, :atom, []}), do: yes(is_atom(value))
  defp do_match(value, {:type, _, :boolean, []}), do: yes(is_boolean(value))
  defp do_match(value, {:type, _, :integer, []}), do: yes(is_integer(value))

  defp do_match(value, {:type, _, :non_neg_integer, []}),
    do: yes(is_integer(value) and value >= 0)

  defp do_match(value, {:type, _, :pos_integer, []}), do: yes(is_integer(value) and value > 0)
  defp do_match(value, {:type, _, :neg_integer, []}), do: yes(is_integer(value) and value < 0)
  defp do_match(value, {:type, _, :float, []}), do: yes(is_float(value))
  defp do_match(value, {:type, _, :number, []}), do: yes(is_number(value))
  defp do_match(value, {:type, _, :binary, []}), do: yes(is_binary(value))

  defp do_match(value, {:type, _, :nonempty_binary, []}),
    do: yes(is_binary(value) and byte_size(value) > 0)

  defp do_match(value, {:type, _, :bitstring, []}), do: yes(is_bitstring(value))

  defp do_match(value, {:type, _, :nonempty_bitstring, []}),
    do: yes(is_bitstring(value) and bit_size(value) > 0)

  defp do_match(value, {:type, _, :byte, []}), do: yes(is_integer(value) and value in 0..255)

  defp do_match(value, {:type, _, :char, []}),
    do: yes(is_integer(value) and value >= 0 and value <= 0x10FFFF)

  defp do_match(value, {:type, _, :pid, []}), do: yes(is_pid(value))
  defp do_match(value, {:type, _, :port, []}), do: yes(is_port(value))
  defp do_match(value, {:type, _, :reference, []}), do: yes(is_reference(value))

  defp do_match(value, {:type, _, :identifier, []}),
    do: yes(is_pid(value) or is_port(value) or is_reference(value))

  defp do_match(value, {:type, _, :module, []}), do: yes(is_atom(value))
  defp do_match(value, {:type, _, :node, []}), do: yes(is_atom(value))
  defp do_match(value, {:type, _, :arity, []}), do: yes(is_integer(value) and value in 0..255)

  defp do_match(value, {:type, _, :timeout, []}),
    do: yes(value == :infinity or (is_integer(value) and value >= 0))

  defp do_match({module, function, arity}, {:type, _, :mfa, []}),
    do: yes(is_atom(module) and is_atom(function) and is_integer(arity) and arity in 0..255)

  defp do_match(_, {:type, _, :mfa, []}), do: :no_match

  defp do_match(value, {:type, _, :struct, []}),
    do: yes(is_map(value) and is_atom(Map.get(value, :__struct__)))

  defp do_match(value, {:type, _, type, []}) when type in [:charlist, :string],
    do: yes(charlist?(value))

  defp do_match(value, {:type, _, type, []}) when type in [:nonempty_charlist, :nonempty_string],
    do: yes(charlist?(value) and not Enum.empty?(value))

  defp do_match(value, {:type, _, :iolist, []}), do: yes(is_list(value) and iodata?(value))
  defp do_match(value, {:type, _, :iodata, []}), do: yes(iodata?(value))

  defp do_match(value, {:type, _, :tuple, :any}), do: yes(is_tuple(value))
  defp do_match(value, {:type, _, :tuple, []}), do: yes(is_tuple(value))

  defp do_match(value, {:type, _, :tuple, elements}) when is_list(elements) do
    if is_tuple(value) and tuple_size(value) == Enum.count(elements) do
      value
      |> Tuple.to_list()
      |> Enum.zip(elements)
      |> Enum.map(fn {element, type} -> do_match(element, type) end)
      |> all_result()
    else
      :no_match
    end
  end

  defp do_match(value, {:type, _, :map, :any}), do: yes(is_map(value))
  defp do_match(value, {:type, _, :map, []}), do: yes(is_map(value))

  defp do_match(value, {:type, _, :map, fields}) when is_list(fields) do
    if is_map(value) do
      fields
      |> Enum.map(&match_map_field(value, &1))
      |> all_result()
    else
      :no_match
    end
  end

  defp do_match([], {:type, _, nil, []}), do: :match
  defp do_match(_, {:type, _, nil, []}), do: :no_match
  defp do_match(value, {:type, _, :list, []}), do: yes(is_list(value))

  defp do_match(value, {:type, _, :list, [element_type]}) do
    if is_list(value) do
      match_list(value, element_type)
    else
      :no_match
    end
  end

  defp do_match(value, {:type, _, :nonempty_list, [element_type]}) do
    if is_list(value) and Enum.any?(value) do
      match_list(value, element_type)
    else
      :no_match
    end
  end

  defp do_match(value, {:type, _, :range, [first, last]}) do
    with {:integer, _, first} <- first,
         {:integer, _, last} <- last do
      yes(is_integer(value) and value >= first and value <= last)
    else
      _ -> :unknown
    end
  end

  defp do_match(value, {:type, _, :fun, []}), do: yes(is_function(value))
  defp do_match(value, {:type, _, :function, []}), do: yes(is_function(value))

  defp do_match(value, {:type, _, :fun, [{:type, _, :product, arguments}, _]}) do
    yes(is_function(value, Enum.count(arguments)))
  end

  defp do_match(_, {:type, _, type, []}) when type in [:none, :no_return], do: :no_match
  defp do_match(_, _), do: :unknown

  defp match_list(list, element_type) do
    list
    |> Enum.map(&do_match(&1, element_type))
    |> all_result()
  end

  defp match_map_field(map, {:type, _, :map_field_exact, [key_type, value_type]}) do
    case literal(key_type) do
      {:ok, key} ->
        if Map.has_key?(map, key) do
          do_match(Map.fetch!(map, key), value_type)
        else
          :no_match
        end

      :error ->
        match_typed_map_entries(map, key_type, value_type, true)
    end
  end

  defp match_map_field(map, {:type, _, :map_field_assoc, [key_type, value_type]}),
    do: match_typed_map_entries(map, key_type, value_type, false)

  defp match_map_field(_, _), do: :unknown

  defp match_typed_map_entries(map, key_type, value_type, required?) do
    matching_values =
      for {key, value} <- Map.to_list(map), do_match(key, key_type) == :match, do: value

    if required? and Enum.empty?(matching_values) do
      :no_match
    else
      matching_values
      |> Enum.map(&do_match(&1, value_type))
      |> all_result()
    end
  end

  defp literal({:atom, _, value}), do: {:ok, value}
  defp literal({:integer, _, value}), do: {:ok, value}
  defp literal({:char, _, value}), do: {:ok, value}
  defp literal({:float, _, value}), do: {:ok, value}
  defp literal({:string, _, value}), do: {:ok, value}
  defp literal(_), do: :error

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
