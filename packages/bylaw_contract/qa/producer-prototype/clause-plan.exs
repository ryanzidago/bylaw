defmodule ProducerClausePlan do
  @moduledoc "Restricted authored-clause translation for the isolated producer experiment."
  @variables [:"$1", :"$2", :"$3", :"$4", :"$5", :"$6", :"$7", :"$8"]

  @doc "Compiles at most sixteen clauses with bounded primitive guards into explicitly sized outcome slots."
  @spec compile(map()) :: {:ok, map()} | {:error, atom()}
  def compile(%{clauses: clauses}) when length(clauses) > 16,
    do: {:error, :clause_capacity}

  def compile(%{mfa: {_, _, arity} = mfa, clauses: clauses})
      when arity >= 0 and arity <= 8 and clauses != [] do
    try do
      clauses = Enum.sort_by(clauses, &elem(&1.id, 4))

      for {entry, position} <- Enum.with_index(clauses, 1) do
        case entry.id do
          {module, function, count, _line, ^position} when {module, function, count} == mfa -> :ok
          _ -> throw(:unsupported_clause)
        end
      end

      {flags, slots, _prior} =
        Enum.reduce(clauses, {[], %{}, false}, fn entry, {flags, slots, prior} ->
          {:clause, _, patterns, guards, _body} = entry.clause
          bound({patterns, guards}, 256)
          if length(patterns) != arity, do: throw(:unsupported_clause)
          variables = Enum.take(@variables, arity)

          {bindings, heads} =
            Enum.zip(patterns, variables)
            |> Enum.reduce({%{}, []}, fn
              {{:var, _, :_}, _variable}, acc ->
                acc

              {{:var, _, name}, variable}, {bindings, heads} ->
                if Map.has_key?(bindings, name), do: throw(:unsupported_clause)
                {Map.put(bindings, name, variable), heads}

              {{:atom, _, value}, variable}, {bindings, heads} ->
                {bindings, [{:"=:=", variable, {:const, value}} | heads]}

              {{:integer, _, value}, variable}, {bindings, heads}
              when value >= -2_147_483_648 and value <= 2_147_483_647 ->
                {bindings, [{:"=:=", variable, value} | heads]}

              _, _ ->
                throw(:unsupported_clause)
            end)

          head = conjunction(heads)

          guard =
            case guards do
              [] ->
                true

              groups ->
                groups
                |> Enum.map(fn group ->
                  group |> Enum.map(&expression(&1, bindings)) |> conjunction()
                end)
                |> disjunction()
            end

          passed = {:andalso, head, guard}
          selected = {:andalso, passed, {:not, prior}}
          rejected = if Enum.empty?(guards), do: false, else: {:andalso, head, {:not, guard}}
          outcomes = [:head_matches, :guard_passes, :selected, :guard_rejections]
          offset = length(flags)

          slots =
            Enum.with_index(outcomes, offset)
            |> Enum.reduce(slots, fn {outcome, slot}, acc ->
              key = {entry.id, outcome}
              if Map.has_key?(acc, key), do: throw(:unsupported_clause)
              Map.put(acc, key, slot)
            end)

          {flags ++ [head, passed, selected, rejected], slots, {:orelse, prior, passed}}
        end)

      flags = List.to_tuple(flags)

      {:ok,
       %{
         mfa: mfa,
         slot_count: max(8, map_size(slots)),
         slots: slots,
         match_spec: [{Enum.take(@variables, arity), [], [{:message, {flags}}, {:return_trace}]}]
       }}
    catch
      :unsupported_clause -> {:error, :unsupported_clause}
    end
  end

  def compile(_), do: {:error, :unsupported_clause}

  defp bound(_, budget) when budget <= 0, do: throw(:unsupported_clause)
  defp bound([], budget), do: budget - 1
  defp bound([head | tail], budget), do: bound(tail, bound(head, budget - 1))

  defp bound(value, budget) when is_tuple(value) do
    if tuple_size(value) >= budget, do: throw(:unsupported_clause)
    bound(Tuple.to_list(value), budget - 1)
  end

  defp bound(_, budget), do: budget - 1

  defp expression({:var, _, name}, bindings) do
    case Map.fetch(bindings, name) do
      {:ok, value} -> value
      :error -> throw(:unsupported_clause)
    end
  end

  defp expression({:integer, _, value}, _)
       when value >= -2_147_483_648 and value <= 2_147_483_647, do: value

  defp expression({:atom, _, value}, _), do: {:const, value}

  defp expression(
         {:call, _, {:remote, _, {:atom, _, :erlang}, {:atom, _, function}}, [argument]},
         bindings
       )
       when function in [:is_integer, :is_atom, :is_binary] do
    {function, expression(argument, bindings)}
  end

  defp expression({:op, _, op, left, right}, bindings) when op in [:andalso, :orelse] do
    {op, expression(left, bindings), expression(right, bindings)}
  end

  defp expression({:op, _, op, {:var, _, _} = left, {:integer, _, _} = right}, bindings)
       when op in [:>, :<, :>=, :"=<", :"=:=", :"=/="] do
    {op, expression(left, bindings), expression(right, bindings)}
  end

  defp expression(_, _), do: throw(:unsupported_clause)
  defp conjunction([]), do: true
  defp conjunction([first | rest]), do: Enum.reduce(rest, first, &{:andalso, &2, &1})
  defp disjunction([]), do: false
  defp disjunction([first | rest]), do: Enum.reduce(rest, first, &{:orelse, &2, &1})
end
