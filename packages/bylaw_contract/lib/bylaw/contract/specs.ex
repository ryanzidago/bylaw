defmodule Bylaw.Contract.Specs do
  @moduledoc false

  alias Bylaw.Contract.FunctionSelection

  alias Bylaw.Contract.TypeMatcher
  alias Bylaw.Contract.TypeExpansion

  @types_cache_key {__MODULE__, :types_cache}
  @max_union_visits 4096

  @spec load(modules :: list(module()), selection :: FunctionSelection.t()) :: map()
  def load(modules, selection \\ :all) do
    Process.put(@types_cache_key, %{})

    try do
      do_load(FunctionSelection.modules(modules, selection), selection)
    after
      Process.delete(@types_cache_key)
    end
  end

  defp do_load(modules, selection) do
    {input_classes, boundaries, return_alternatives, warnings} =
      Enum.reduce(modules, {[], [], [], []}, fn module,
                                                {input_classes, boundaries, return_alternatives,
                                                 warnings} ->
        case load_module(module, selection) do
          {:ok, module_classes, module_boundaries, module_returns, module_warnings} ->
            {
              module_classes ++ input_classes,
              module_boundaries ++ boundaries,
              module_returns ++ return_alternatives,
              module_warnings ++ warnings
            }

          {:error, reason} ->
            {input_classes, boundaries, return_alternatives, [reason | warnings]}
        end
      end)

    input_sort_key = &{&1.module, &1.function, &1.arity, &1.clause, &1.argument, &1.position}
    return_sort_key = &{&1.module, &1.function, &1.arity, &1.clause, &1.position}

    %{
      input_classes: Enum.sort_by(input_classes, input_sort_key),
      boundaries: Enum.sort_by(boundaries, input_sort_key),
      return_alternatives: Enum.sort_by(return_alternatives, return_sort_key),
      warnings: Enum.reverse(warnings)
    }
  end

  defp load_module(module, selection) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         {:ok, specs} <- Code.Typespec.fetch_specs(module) do
      source_file = module.module_info(:compile) |> Keyword.get(:source) |> normalize_file()

      {input_classes, boundaries, return_alternatives, warnings} =
        extract_specs(
          module,
          Enum.filter(specs, fn {{function, arity}, _} ->
            FunctionSelection.member?(selection, module, function, arity)
          end),
          source_file
        )

      {:ok, input_classes, boundaries, return_alternatives, warnings}
    else
      {:error, reason} ->
        {:error, "could not load #{inspect(module)}: #{inspect(reason)}"}

      :error ->
        {:error, "#{inspect(module)} has no persisted typespecs"}
    end
  end

  defp extract_specs(module, specs, source_file) do
    Enum.reduce(specs, {[], [], [], []}, fn {{function, arity}, clauses}, acc ->
      clauses
      |> Enum.with_index(1)
      |> Enum.reduce(acc, fn {clause, clause_number},
                             {input_classes, boundaries, return_alternatives, warnings} ->
        case spec_signature(clause) do
          {:ok, arguments, return} ->
            spec = spec_context(function, clause, source_file)

            {found_classes, found_boundaries} =
              extract_arguments(module, function, arity, clause_number, arguments, spec)

            found_returns =
              extract_return(module, function, arity, clause_number, return, spec)

            {
              found_classes ++ input_classes,
              found_boundaries ++ boundaries,
              found_returns ++ return_alternatives,
              warnings
            }

          :unsupported ->
            warning =
              "ignored unsupported spec form #{inspect(module)}.#{function}/#{arity} " <>
                "clause #{clause_number}"

            {input_classes, boundaries, return_alternatives, [warning | warnings]}
        end
      end)
    end)
  end

  defp spec_signature({:type, _, :fun, [{:type, _, :product, arguments}, return]}) do
    {:ok, arguments, return}
  end

  defp spec_signature({:type, _, :bounded_fun, [function_type, constraints]}) do
    with {:ok, arguments, return} <- spec_signature(function_type),
         {:ok, bindings} <- constraint_bindings(constraints) do
      {:ok, substitute(arguments, bindings), substitute(return, bindings)}
    end
  end

  defp spec_signature(_), do: :unsupported

  defp constraint_bindings(constraints) do
    Enum.reduce_while(constraints, {:ok, %{}}, fn
      {:type, _, :constraint, [{:atom, _, :is_subtype}, [{:var, _, variable_name}, type]]},
      {:ok, bindings} ->
        {:cont, {:ok, Map.put(bindings, variable_name, type)}}

      _, _ ->
        {:halt, :unsupported}
    end)
  end

  defp extract_arguments(module, function, arity, clause, arguments, spec) do
    arguments
    |> Enum.with_index(1)
    |> Enum.reduce({[], []}, fn {argument_type, argument_number}, {classes, boundaries} ->
      members = flatten_union(argument_type, module, %{})

      class_specs =
        case members do
          [_] -> partition_single_type(hd(members))
          union_members -> Enum.map(union_members, &union_member_class/1)
        end

      argument_classes =
        class_specs
        |> Enum.with_index(1)
        |> Enum.map(fn {class, position} ->
          Map.merge(class, %{
            id: {:input_class, module, function, arity, clause, argument_number, position},
            module: module,
            function: function,
            arity: arity,
            clause: clause,
            argument: argument_number,
            position: position,
            supported?: TypeMatcher.supported?(class.match_type),
            spec_file: spec.file,
            spec_line: spec.line,
            spec_source: spec.source
          })
        end)

      argument_boundaries =
        members
        |> Enum.flat_map(&range_boundaries/1)
        |> merge_boundaries()
        |> Enum.with_index(1)
        |> Enum.map(fn {boundary, position} ->
          Map.merge(boundary, %{
            id: {:boundary, module, function, arity, clause, argument_number, position},
            module: module,
            function: function,
            arity: arity,
            clause: clause,
            argument: argument_number,
            position: position,
            supported?: true,
            spec_file: spec.file,
            spec_line: spec.line,
            spec_source: spec.source
          })
        end)

      {argument_classes ++ classes, argument_boundaries ++ boundaries}
    end)
  end

  defp extract_return(module, function, arity, clause, return_type, spec) do
    members = flatten_union(return_type, module, %{})

    if Enum.count(members) > 1 do
      members
      |> Enum.with_index(1)
      |> Enum.map(fn {{display_type, match_type}, position} ->
        %{
          id: {:return_alternative, module, function, arity, clause, position},
          module: module,
          function: function,
          arity: arity,
          clause: clause,
          position: position,
          label: format_type(display_type),
          match_type: match_type,
          supported?: TypeMatcher.supported?(match_type),
          spec_file: spec.file,
          spec_line: spec.line,
          spec_source: spec.source
        }
      end)
    else
      []
    end
  end

  defp union_member_class({display_type, match_type}) do
    %{
      label: format_type(display_type_for_range(display_type, match_type)),
      match_type: match_type,
      partition: :union_member
    }
  end

  defp partition_single_type({display_type, {:bylaw_contract, :type_graph, root, nodes}}) do
    {display_type, root}
    |> partition_single_type()
    |> Enum.map(fn class ->
      %{class | match_type: TypeExpansion.wrap(class.match_type, nodes)}
    end)
  end

  defp partition_single_type({display_type, match_type}) do
    source_label = format_type(display_type)
    partitions_for(match_type, source_label)
  end

  defp partitions_for({:type, _, :integer, []}, source_label) do
    [
      partition("negative", {:type, 0, :neg_integer, []}, :negative, source_label),
      partition("zero", {:integer, 0, 0}, :zero, source_label),
      partition("positive", {:type, 0, :pos_integer, []}, :positive, source_label)
    ]
  end

  defp partitions_for({:type, _, :non_neg_integer, []}, source_label) do
    [
      partition("zero", {:integer, 0, 0}, :zero, source_label),
      partition("positive", {:type, 0, :pos_integer, []}, :positive, source_label)
    ]
  end

  defp partitions_for({:type, _, :pos_integer, []} = match_type, source_label) do
    [partition("positive", match_type, :positive, source_label)]
  end

  defp partitions_for({:type, _, :neg_integer, []} = match_type, source_label) do
    [partition("negative", match_type, :negative, source_label)]
  end

  defp partitions_for(
         {:type, _, :range, [{:integer, _, first}, {:integer, _, last}]},
         source_label
       )
       when first <= last do
    range_partitions(first, last, source_label)
  end

  defp partitions_for({:type, _, :list, [element_type]}, source_label) do
    list_partitions(element_type, [:empty, :singleton, :multiple], source_label)
  end

  defp partitions_for({:type, _, :list, []}, source_label) do
    list_partitions({:type, 0, :any, []}, [:empty, :singleton, :multiple], source_label)
  end

  defp partitions_for({:type, _, :nonempty_list, [element_type]}, source_label) do
    list_partitions(element_type, [:singleton, :multiple], source_label)
  end

  defp partitions_for({:type, _, :binary, []}, source_label) do
    [
      partition("empty", {:bylaw_contract, :binary_size, :empty}, :empty, source_label),
      partition("non-empty", {:bylaw_contract, :binary_size, :nonempty}, :nonempty, source_label)
    ]
  end

  defp partitions_for({:type, _, :nonempty_binary, []}, source_label) do
    [partition("non-empty", {:bylaw_contract, :binary_size, :nonempty}, :nonempty, source_label)]
  end

  defp partitions_for({:type, _, :boolean, []}, source_label) do
    [
      partition("false", {:atom, 0, false}, false, source_label),
      partition("true", {:atom, 0, true}, true, source_label)
    ]
  end

  defp partitions_for(match_type, source_label) do
    [partition(source_label, match_type, :declared_type, source_label)]
  end

  defp range_partitions(first, last, source_label) when first == last do
    [
      partition(
        "minimum/maximum (#{first})",
        {:integer, 0, first},
        :minimum_maximum,
        source_label
      )
    ]
  end

  defp range_partitions(first, last, source_label) when first + 1 == last do
    [
      partition("minimum (#{first})", {:integer, 0, first}, :minimum, source_label),
      partition("maximum (#{last})", {:integer, 0, last}, :maximum, source_label)
    ]
  end

  defp range_partitions(first, last, source_label) do
    [
      partition("minimum (#{first})", {:integer, 0, first}, :minimum, source_label),
      partition(
        "interior (#{first + 1}..#{last - 1})",
        {:type, 0, :range, [{:integer, 0, first + 1}, {:integer, 0, last - 1}]},
        :interior,
        source_label
      ),
      partition("maximum (#{last})", {:integer, 0, last}, :maximum, source_label)
    ]
  end

  defp list_partitions(element_type, lengths, source_label) do
    Enum.map(lengths, fn length ->
      label =
        if length == :multiple do
          "multiple"
        else
          Atom.to_string(length)
        end

      partition(
        label,
        {:bylaw_contract, :list_length, length, element_type},
        length,
        source_label
      )
    end)
  end

  defp partition(label, match_type, partition, source_label) do
    %{
      label: label,
      match_type: match_type,
      partition: partition,
      source_label: source_label
    }
  end

  defp range_boundaries({display_type, match_type}) do
    case match_type do
      {:type, _, :range, [{:integer, _, first}, {:integer, _, last}]} when first <= last ->
        source_label = format_type(display_type_for_range(display_type, match_type))

        if first == last do
          [boundary(first, [:minimum, :maximum], source_label)]
        else
          [
            boundary(first, [:minimum], source_label),
            boundary(last, [:maximum], source_label)
          ]
        end

      _ ->
        []
    end
  end

  defp boundary(value, roles, source_label) do
    %{
      label: Integer.to_string(value),
      value: value,
      roles: roles,
      source_labels: [source_label],
      match_type: {:integer, 0, value}
    }
  end

  defp merge_boundaries(boundaries) do
    boundaries
    |> Enum.group_by(& &1.value)
    |> Enum.sort_by(fn {value, _} -> value end)
    |> Enum.map(fn {_, same_value} ->
      first = hd(same_value)

      %{
        first
        | roles: Enum.uniq(Enum.flat_map(same_value, & &1.roles)),
          source_labels: Enum.uniq(Enum.flat_map(same_value, & &1.source_labels))
      }
    end)
  end

  defp display_type_for_range(_, {:type, _, :range, _} = match_type),
    do: match_type

  defp display_type_for_range(display_type, _), do: display_type

  defp flatten_union(type, module, seen) do
    case visit_union(type, module, seen, @max_union_visits) do
      {:ok, members, _remaining} -> members
      :limit -> [{type, {:unsupported, {:union_expansion_limit, @max_union_visits}}}]
    end
  end

  defp visit_union(_type, _module, _seen, 0), do: :limit

  defp visit_union(type, module, seen, remaining),
    do: flatten_members(type, module, seen, remaining - 1)

  defp flatten_members({:ann_type, _, [_, type]}, module, seen, remaining),
    do: visit_union(type, module, seen, remaining)

  defp flatten_members({:type, _, :union, members}, module, seen, remaining) do
    Enum.reduce_while(members, {:ok, [], remaining}, fn member, {:ok, groups, remaining} ->
      case visit_union(member, module, seen, remaining) do
        {:ok, members, remaining} -> {:cont, {:ok, [members | groups], remaining}}
        :limit -> {:halt, :limit}
      end
    end)
    |> case do
      {:ok, groups, remaining} -> {:ok, groups |> Enum.reverse() |> List.flatten(), remaining}
      :limit -> :limit
    end
  end

  defp flatten_members({:user_type, _, name, arguments} = original, module, seen, remaining),
    do: flatten_alias(original, module, name, arguments, seen, remaining)

  defp flatten_members(
         {:remote_type, _, [{:atom, _, module}, {:atom, _, name}, arguments]} = original,
         _caller,
         seen,
         remaining
       ),
       do: flatten_alias(original, module, name, arguments, seen, remaining)

  defp flatten_members(type, module, _seen, remaining),
    do: {:ok, [{type, expand(type, module, %{})}], remaining}

  defp flatten_alias(original, module, name, arguments, seen, remaining) do
    key = {module, name, Enum.count(arguments)}

    if Map.has_key?(seen, key) do
      {:ok, [{original, {:unsupported, {:recursive_type, key}}}], remaining}
    else
      case resolve(module, name, arguments) do
        {:ok, resolved} ->
          case visit_union(resolved, module, Map.put(seen, key, true), remaining) do
            {:ok, [{_display, match_type}], remaining} ->
              {:ok, [{original, match_type}], remaining}

            other ->
              other
          end

        :error ->
          {:ok, [{original, {:unsupported, {:unknown_type, key}}}], remaining}
      end
    end
  end

  defp expand(type, module, _seen), do: TypeExpansion.expand(type, module, &resolve/3)

  defp resolve(module, name, arguments) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         {:ok, types} <- fetch_types(module),
         {visibility, {^name, body, variables}} <-
           Enum.find(types, fn
             {_, {type_name, _, variables}} ->
               type_name == name and Enum.count(variables) == Enum.count(arguments)

             _ ->
               false
           end),
         true <- visibility != :opaque do
      bindings =
        variables
        |> Enum.zip(arguments)
        |> Map.new(fn {{:var, _, variable_name}, value} -> {variable_name, value} end)

      {:ok, substitute(body, bindings)}
    else
      _ -> :error
    end
  end

  defp fetch_types(module) do
    cache = Process.get(@types_cache_key, %{})

    case Map.fetch(cache, module) do
      {:ok, result} ->
        result

      :error ->
        result = Code.Typespec.fetch_types(module)
        Process.put(@types_cache_key, Map.put(cache, module, result))
        result
    end
  end

  defp substitute({:var, _, name} = variable, bindings), do: Map.get(bindings, name, variable)

  defp substitute(tuple, bindings) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&substitute(&1, bindings))
    |> List.to_tuple()
  end

  defp substitute(list, bindings) when is_list(list) do
    Enum.map(list, &substitute(&1, bindings))
  end

  defp substitute(other, _), do: other

  defp format_type(type) do
    {:"::", _, [_, quoted]} = Code.Typespec.type_to_quoted({:bylaw_contract_member, type, []})
    Macro.to_string(quoted)
  rescue
    _ -> inspect(type)
  end

  defp spec_context(function, clause, source_file) do
    %{
      file: source_file,
      line: spec_line(clause),
      source: "@spec " <> Macro.to_string(Code.Typespec.spec_to_quoted(function, clause))
    }
  end

  defp spec_line({_, annotation, _, _}), do: :erl_anno.line(annotation)

  defp normalize_file(file) when is_binary(file), do: file
  defp normalize_file(file) when is_list(file), do: List.to_string(file)
  defp normalize_file(_), do: nil
end
