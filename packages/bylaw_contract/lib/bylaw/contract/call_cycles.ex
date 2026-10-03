defmodule Bylaw.Contract.CallCycles do
  @moduledoc false

  # Finds the functions of a module that can reach themselves. Observing the
  # return value of such a function would remove tail-call optimisation, so the
  # instrumenter leaves their returns alone.

  @doc false
  @spec recursive(forms :: list(term()), module :: module()) :: MapSet.t({atom(), arity()})
  def recursive(forms, module) do
    graph =
      for {:function, _annotation, name, arity, clauses} <- forms, into: %{} do
        {{name, arity}, clauses |> calls(module, MapSet.new()) |> MapSet.to_list()}
      end

    graph
    |> Map.keys()
    |> Enum.filter(&reaches?(graph, Map.get(graph, &1, []), &1, MapSet.new()))
    |> MapSet.new()
  end

  defp reaches?(graph, frontier, target, seen) do
    Enum.any?(frontier, fn callee ->
      cond do
        callee == target -> true
        MapSet.member?(seen, callee) -> false
        true -> reaches?(graph, Map.get(graph, callee, []), target, MapSet.put(seen, callee))
      end
    end)
  end

  defp calls({:call, _annotation, {:atom, _, name}, arguments}, module, acc),
    do: calls(arguments, module, MapSet.put(acc, {name, Enum.count(arguments)}))

  defp calls(
         {:call, _annotation, {:remote, _, {:atom, _, module}, {:atom, _, name}}, arguments},
         module,
         acc
       ),
       do: calls(arguments, module, MapSet.put(acc, {name, Enum.count(arguments)}))

  defp calls({:fun, _annotation, {:function, name, arity}}, _module, acc),
    do: MapSet.put(acc, {name, arity})

  defp calls(
         {:fun, _annotation,
          {:function, {:atom, _, module}, {:atom, _, name}, {:integer, _, arity}}},
         module,
         acc
       ),
       do: MapSet.put(acc, {name, arity})

  defp calls(tuple, module, acc) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> calls(module, acc)

  defp calls(list, module, acc) when is_list(list),
    do: Enum.reduce(list, acc, &calls(&1, module, &2))

  defp calls(_other, _module, acc), do: acc
end
