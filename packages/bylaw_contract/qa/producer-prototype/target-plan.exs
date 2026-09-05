defmodule ProducerTargetPlan do
  @moduledoc "Bounded target metadata translation for the isolated native experiment."

  @doc "Compiles at most eight targets, rejecting the whole plan on unsupported metadata."
  @spec compile(list({:call | :return, map()})) :: {:ok, map()} | {:error, term()}
  def compile([]), do: {:error, :empty_plan}
  def compile(entries) when length(entries) > 8, do: {:error, :target_capacity}

  def compile(entries) do
    ids = Enum.map(entries, fn {_, target} -> target.id end)

    if length(Enum.uniq(ids)) != length(ids) do
      {:error, :duplicate_target_ids}
    else
      entries
      |> Enum.sort_by(fn {_, target} -> target.id end)
      |> Enum.reduce_while({:ok, [], []}, fn {event, target}, {:ok, ids, rules} ->
        case rule(event, target) do
          {:ok, rule} -> {:cont, {:ok, [target.id | ids], [rule | rules]}}
          error -> {:halt, error}
        end
      end)
      |> finish()
    end
  end

  defp finish({:error, _} = error), do: error

  defp finish({:ok, ids, rules}) do
    rules = Enum.reverse(rules)
    mfas = rules |> Enum.map(fn {m, f, a, _, _, _} -> {m, f, a} end) |> Enum.uniq() |> Enum.sort()

    if Enum.sum(Enum.map(rules, &node_count(elem(&1, 5)))) > 64 do
      {:error, :metadata_capacity}
    else
      {:ok,
       %{slots: ids |> Enum.reverse() |> Enum.with_index() |> Map.new(), rules: rules, mfas: mfas}}
    end
  end

  defp node_count({:tuple, children}), do: 1 + Enum.sum(Enum.map(children, &node_count/1))
  defp node_count(_), do: 1

  defp rule(event, %{module: m, function: f, arity: a} = target)
       when is_atom(m) and is_atom(f) and is_integer(a) and a >= 0 and a <= 255 and
              event in [:call, :return] do
    argument = if event == :return, do: 0, else: Map.get(target, :argument)

    cond do
      event == :call and not (is_integer(argument) and argument >= 1 and argument <= a) ->
        {:error, {:invalid_target, target.id}}

      Map.get(target, :supported?) != true ->
        {:error, {:unsupported_target, target.id}}

      true ->
        case descriptor(Map.get(target, :match_type)) do
          :unsupported -> {:error, {:unsupported_target, target.id}}
          descriptor -> {:ok, {m, f, a, event, argument, descriptor}}
        end
    end
  end

  defp rule(_, target), do: {:error, {:invalid_target, target.id}}

  defp descriptor(type) do
    try do
      {descriptor, _remaining} = lower(type, %{}, 8, 64)
      descriptor
    catch
      :unsupported -> :unsupported
    end
  end

  defp lower(_, _, depth, remaining) when depth <= 0 or remaining <= 0,
    do: throw(:unsupported)

  defp lower({:bylaw_contract, :type_graph, root, nodes}, _, depth, remaining)
       when is_map(nodes) and map_size(nodes) <= 64 do
    lower(root, nodes, depth - 1, remaining - 1)
  end

  defp lower({:bylaw_contract, :type_ref, key}, nodes, depth, remaining) do
    case Map.fetch(nodes, key) do
      {:ok, {type, true}} -> lower(type, nodes, depth - 1, remaining - 1)
      _ -> throw(:unsupported)
    end
  end

  defp lower({:type, _, :tuple, children}, nodes, depth, remaining) when is_list(children) do
    {children, excess} = Enum.split(children, 8)
    if not Enum.empty?(excess), do: throw(:unsupported)

    {descriptors, remaining} =
      Enum.map_reduce(children, remaining - 1, fn child, budget ->
        lower(child, nodes, depth - 1, budget)
      end)

    {{:tuple, descriptors}, remaining}
  end

  defp lower(type, _, _, remaining) do
    case leaf_descriptor(type) do
      :unsupported -> throw(:unsupported)
      descriptor -> {descriptor, remaining - 1}
    end
  end

  defp leaf_descriptor({:type, _, type, []})
       when type in [:integer, :atom, :binary, :non_neg_integer, :neg_integer, :pos_integer],
       do: type

  defp leaf_descriptor({:atom, _, value}) when is_atom(value), do: {:literal_atom, value}
  defp leaf_descriptor({:type, _, :list, [{:type, _, :integer, []}]}), do: :integer_list

  defp leaf_descriptor({:bylaw_contract, :list_length, :empty, {:type, _, :integer, []}}),
    do: :empty_integer_list

  defp leaf_descriptor({:bylaw_contract, :list_length, :singleton, {:type, _, :integer, []}}),
    do: :singleton_integer_list

  defp leaf_descriptor({:bylaw_contract, :list_length, :multiple, {:type, _, :integer, []}}),
    do: :multiple_integer_list

  defp leaf_descriptor(_), do: :unsupported
end
