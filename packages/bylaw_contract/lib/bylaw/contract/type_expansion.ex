defmodule Bylaw.Contract.TypeExpansion do
  @moduledoc false

  alias Bylaw.Contract.TypeMatcher

  @max_aliases 4096

  @doc false
  @spec expand(type :: term(), module :: module(), resolve :: function()) :: term()
  def expand(type, module, resolve) do
    state = %{nodes: %{}, cache: %{}, remaining: @max_aliases, resolve: resolve}
    {root, state} = expand_type(type, module, %{}, state)
    graph = wrap(root, state.nodes)

    if TypeMatcher.supported?(graph) do
      graph
    else
      compact_unsupported(root, state.nodes)
    end
  end

  @doc false
  @spec wrap(root :: term(), nodes :: map()) :: term()
  def wrap(root, nodes) when map_size(nodes) == 0, do: root
  def wrap(root, nodes), do: {:bylaw_contract, :type_graph, root, nodes}

  defp expand_type({:bylaw_contract, :type_ref, _} = ref, _module, _seen, state),
    do: {ref, state}

  defp expand_type({:ann_type, _, [_, type]}, module, seen, state),
    do: expand_type(type, module, seen, state)

  defp expand_type({:user_type, _, name, arguments}, module, seen, state),
    do: expand_alias(module, name, arguments, module, seen, state)

  defp expand_type(
         {:remote_type, _, [{:atom, _, remote_module}, {:atom, _, name}, arguments]},
         module,
         seen,
         state
       ),
       do: expand_alias(remote_module, name, arguments, module, seen, state)

  defp expand_type({:type, _, :fun, [{:type, _, :product, _}, _]} = type, _module, _seen, state),
    do: {type, state}

  defp expand_type({:type, annotation, kind, children}, module, seen, state)
       when kind in [:tuple, :union, :list, :nonempty_list] and is_list(children) do
    case expand_members(children, module, seen, state) do
      {:ok, expanded, state} ->
        {{:type, annotation, kind, expanded}, state}

      {:unsupported, reason, state} when kind in [:list, :nonempty_list] ->
        {{:type, annotation, kind, [reason]}, state}

      {:unsupported, reason, state} ->
        {reason, state}
    end
  end

  defp expand_type({:type, annotation, :map, fields}, module, seen, state) when is_list(fields) do
    Enum.reduce_while(fields, {[], state}, fn field, {fields, state} ->
      case expand_field(field, module, seen, state) do
        {:ok, field, state} -> {:cont, {[field | fields], state}}
        {:unsupported, reason, state} -> {:halt, {reason, state}}
      end
    end)
    |> case do
      {fields, state} when is_list(fields) ->
        {{:type, annotation, :map, Enum.reverse(fields)}, state}

      {reason, state} ->
        {reason, state}
    end
  end

  defp expand_type(tuple, module, seen, state) when is_tuple(tuple) do
    {items, state} = expand_type(Tuple.to_list(tuple), module, seen, state)
    {List.to_tuple(items), state}
  end

  defp expand_type(list, module, seen, state) when is_list(list),
    do: Enum.map_reduce(list, state, &expand_type(&1, module, seen, &2))

  defp expand_type(other, _module, _seen, state), do: {other, state}

  defp expand_members(children, module, seen, state) do
    Enum.reduce_while(children, {:ok, [], state}, fn child, {:ok, children, state} ->
      {child, state} = expand_type(child, module, seen, state)

      if TypeMatcher.supported?(wrap(child, state.nodes)) do
        {:cont, {:ok, [child | children], state}}
      else
        {:halt, {:unsupported, unsupported(child, state.nodes), state}}
      end
    end)
    |> case do
      {:ok, children, state} -> {:ok, Enum.reverse(children), state}
      other -> other
    end
  end

  defp expand_field({:type, annotation, kind, children}, module, seen, state)
       when kind in [:map_field_exact, :map_field_assoc] do
    case expand_members(children, module, seen, state) do
      {:ok, children, state} -> {:ok, {:type, annotation, kind, children}, state}
      other -> other
    end
  end

  defp expand_field(_field, _module, _seen, state),
    do: {:unsupported, {:unsupported, :unsupported_map_field}, state}

  defp compact_unsupported({:type, annotation, kind, [child]}, nodes)
       when kind in [:list, :nonempty_list],
       do: {:type, annotation, kind, [unsupported(child, nodes)]}

  defp compact_unsupported({:bylaw_contract, :type_ref, id}, nodes) do
    {body, _supported?} = Map.fetch!(nodes, id)
    compact_unsupported(body, nodes)
  end

  defp compact_unsupported(type, nodes), do: unsupported(type, nodes)

  defp unsupported({:unsupported, _} = reason, _nodes), do: reason

  defp unsupported({:bylaw_contract, :type_ref, id}, nodes) do
    {body, _supported?} = Map.fetch!(nodes, id)
    unsupported(body, nodes)
  end

  defp unsupported(_type, _nodes), do: {:unsupported, :unsupported_type}

  defp expand_alias(module, name, arguments, caller, seen, state) do
    key = {module, name, Enum.count(arguments)}

    if Map.has_key?(seen, key) do
      {{:unsupported, {:recursive_type, key}}, state}
    else
      {arguments, state} = expand_type(arguments, caller, seen, state)
      cache_key = {key, arguments, seen}

      case Map.fetch(state.cache, cache_key) do
        {:ok, reference} ->
          {reference, state}

        :error ->
          resolve_alias(module, name, arguments, key, cache_key, seen, state)
      end
    end
  end

  defp resolve_alias(
         _module,
         _name,
         _arguments,
         _key,
         _cache_key,
         _seen,
         %{remaining: 0} = state
       ),
       do: {{:unsupported, {:type_expansion_limit, @max_aliases}}, state}

  defp resolve_alias(module, name, arguments, key, cache_key, seen, state) do
    state = %{state | remaining: state.remaining - 1}

    case state.resolve.(module, name, arguments) do
      {:ok, resolved} ->
        {body, state} = expand_type(resolved, module, Map.put(seen, key, true), state)
        id = map_size(state.nodes)
        reference = {:bylaw_contract, :type_ref, id}
        supported? = TypeMatcher.supported?(wrap(body, state.nodes))

        state = %{
          state
          | nodes: Map.put(state.nodes, id, {body, supported?}),
            cache: Map.put(state.cache, cache_key, reference)
        }

        {reference, state}

      :error ->
        {{:unsupported, {:unknown_type, key}}, state}
    end
  end
end
