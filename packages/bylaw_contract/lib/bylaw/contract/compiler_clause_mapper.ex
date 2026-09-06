defmodule Bylaw.Contract.CompilerClauseMapper do
  @moduledoc false

  if Version.match?(System.version(), "~> 1.20") do
    alias Module.Types.Descr

    @doc false
    @spec map(forms :: list(), module :: module(), rules :: list(map())) :: list(map())
    def map(forms, module, rules) do
      rules_by_function = Enum.group_by(rules, &{&1.function, &1.arity})

      Enum.flat_map(forms, fn
        {:function, _, function, arity, clauses} ->
          case Map.fetch(rules_by_function, {function, arity}) do
            {:ok, function_rules} ->
              map_function(module, function, arity, clauses, function_rules)

            :error ->
              []
          end

        _ ->
          []
      end)
    end

    defp map_function(module, function, arity, clauses, rules) do
      result =
        clauses
        |> Enum.with_index(1)
        |> Enum.reduce_while({[], Descr.none()}, fn
          {{:clause, _, arguments, guards, _body}, index}, {mapped, excluded} ->
            {domain, exact?} = argument_domain(arguments)
            remaining = Descr.difference(domain, excluded)
            output_ids = compatible_outputs(remaining, rules)

            if MapSet.size(output_ids) == 1 do
              rule = %{
                module: module,
                function: function,
                arity: arity,
                index: index,
                output_ids: output_ids
              }

              # Approximate heads and guarded clauses cannot exclude all their possible inputs.
              excluded =
                if exact? and Enum.empty?(guards) do
                  Descr.union(excluded, domain)
                else
                  excluded
                end

              {:cont, {[rule | mapped], excluded}}
            else
              {:halt, :ambiguous}
            end
        end)

      case result do
        {mapped, _excluded} ->
          if outputs(mapped) == outputs(rules) do
            Enum.reverse(mapped)
          else
            []
          end

        :ambiguous ->
          []
      end
    end

    defp outputs(rules),
      do: Enum.reduce(rules, MapSet.new(), &MapSet.union(&1.output_ids, &2))

    defp compatible_outputs(domain, rules) do
      Enum.reduce(rules, MapSet.new(), fn rule, outputs ->
        if Descr.disjoint?(domain, rule.argument_domain) do
          outputs
        else
          MapSet.union(outputs, rule.output_ids)
        end
      end)
    end

    defp argument_domain(arguments) do
      {types, exact?} = patterns(arguments)
      variables = variables(arguments)
      {Descr.tuple(types), exact? and Enum.count(variables) == MapSet.size(MapSet.new(variables))}
    end

    defp patterns(patterns) do
      Enum.map_reduce(patterns, true, fn pattern, exact? ->
        {type, pattern_exact?} = pattern(pattern)
        {type, exact? and pattern_exact?}
      end)
    end

    defp pattern({:var, _, _}), do: {Descr.term(), true}
    defp pattern({:atom, _, atom}), do: {Descr.atom([atom]), true}
    defp pattern({nil, _}), do: {Descr.empty_list(), true}

    defp pattern({:tuple, _, elements}) do
      {types, exact?} = patterns(elements)
      {Descr.tuple(types), exact?}
    end

    defp pattern({:match, _, left, right}) do
      {left, left_exact?} = pattern(left)
      {right, right_exact?} = pattern(right)
      {Descr.intersection(left, right), left_exact? and right_exact?}
    end

    defp pattern({:integer, _, _}), do: {Descr.integer(), false}
    defp pattern({:float, _, _}), do: {Descr.float(), false}
    defp pattern({:bin, _, _}), do: {Descr.bitstring(), false}
    defp pattern({:cons, _, _, _}), do: {Descr.non_empty_list(Descr.term(), Descr.term()), false}
    defp pattern({:map, _, _}), do: {Descr.open_map(), false}
    defp pattern(_), do: {Descr.term(), false}

    defp variables(term) when is_list(term), do: Enum.flat_map(term, &variables/1)
    defp variables({:var, _, :_}), do: []
    defp variables({:var, _, name}), do: [name]
    defp variables(term) when is_tuple(term), do: term |> Tuple.to_list() |> variables()
    defp variables(_), do: []
  else
    @doc false
    @spec map(forms :: list(), module :: module(), rules :: list(map())) :: list(map())
    def map(_forms, _module, _rules), do: []
  end
end
