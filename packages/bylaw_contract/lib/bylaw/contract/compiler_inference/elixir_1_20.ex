defmodule Bylaw.Contract.CompilerInference.Elixir120 do
  @moduledoc false

  alias Bylaw.Contract.CompilerTypeMatcher
  alias Module.Types.Descr

  @checker_version :elixir_checker_v8

  @doc false
  @spec checker_version() :: atom()
  def checker_version, do: @checker_version

  @doc false
  @spec return_alternatives(module :: module(), exports :: list()) ::
          {:ok, %{return_alternatives: list(map()), inference_rules: list(map())}}
          | {:error, String.t()}
  def return_alternatives(module, exports) do
    decoded = Enum.map(exports, &decode_export(module, &1))

    alternatives =
      decoded
      |> Enum.flat_map(& &1.return_alternatives)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(&{&1.module, &1.function, &1.arity, &1.label})

    inference_rules =
      decoded
      |> Enum.flat_map(& &1.inference_rules)
      |> Enum.sort_by(&{&1.module, &1.function, &1.arity, &1.index})

    {:ok, %{return_alternatives: alternatives, inference_rules: inference_rules}}
  rescue
    error ->
      {:error,
       "could not decode Elixir checker version #{inspect(@checker_version)}: #{Exception.message(error)}"}
  end

  defp decode_export(
         module,
         {{function, arity}, %{sig: {:infer, _domain, clauses}}}
       ) do
    decoded_clauses = Enum.map(clauses, &decode_clause/1)

    return_types =
      clauses
      |> Enum.map(fn {_arguments, return_type} -> return_type end)
      |> Enum.reduce(Descr.none(), &Descr.union/2)
      |> Descr.to_quoted()
      |> unwrap_dynamic()
      |> flatten_union()

    if Enum.count(return_types) > 1 do
      runtime_safe? = Enum.all?(return_types, &finite_discriminant?/1)

      alternatives =
        return_types
        |> Enum.with_index(1)
        |> Enum.map(fn {match_type, index} ->
          label = Macro.to_string(match_type)

          %{
            id: {:compiler_return, module, function, arity, index, label},
            module: module,
            function: function,
            arity: arity,
            label: label,
            match_type: match_type,
            supported?: CompilerTypeMatcher.supported?(match_type),
            runtime_safe?: runtime_safe?,
            checker_version: @checker_version
          }
        end)

      ids_by_label = Map.new(alternatives, &{&1.label, &1.id})

      inference_rules =
        exact_inference_rules(module, function, arity, decoded_clauses, ids_by_label)

      inferable_ids = inferable_ids(inference_rules, runtime_safe?)

      return_alternatives =
        Enum.map(alternatives, fn alternative ->
          Map.put(alternative, :inferable?, MapSet.member?(inferable_ids, alternative.id))
        end)

      %{return_alternatives: return_alternatives, inference_rules: inference_rules}
    else
      empty_decoded_export()
    end
  end

  defp decode_export(_module, _export), do: empty_decoded_export()

  defp exact_inference_rules(module, function, arity, clauses, ids_by_label) do
    rules =
      clauses
      |> Enum.with_index(1)
      |> Enum.map(fn {clause, index} ->
        output_ids =
          clause.return_types
          |> Enum.map(&Macro.to_string/1)
          |> Enum.map(&Map.get(ids_by_label, &1))
          |> MapSet.new()

        if MapSet.member?(output_ids, nil) do
          nil
        else
          %{
            module: module,
            function: function,
            arity: arity,
            index: index,
            argument_types: clause.argument_types,
            argument_domain: clause.argument_domain,
            arguments_supported?: arguments_supported?(clause.argument_types, arity),
            output_ids: output_ids
          }
        end
      end)

    if Enum.any?(rules, &is_nil/1) do
      []
    else
      rules
    end
  end

  defp decode_clause({arguments, return_type}) do
    %{
      argument_types: decode_arguments(arguments),
      argument_domain: argument_domain(arguments),
      return_types: return_type |> Descr.to_quoted() |> unwrap_dynamic() |> flatten_union()
    }
  end

  defp argument_domain(arguments) when is_list(arguments),
    do: arguments |> Enum.map(&Descr.upper_bound/1) |> Descr.tuple()

  defp argument_domain(_arguments), do: Descr.term()

  defp decode_arguments(arguments) when is_list(arguments) do
    Enum.map(arguments, fn argument ->
      argument
      |> Descr.to_quoted()
      |> unwrap_dynamic()
    end)
  end

  defp decode_arguments(_arguments), do: nil

  defp arguments_supported?(argument_types, arity)
       when is_list(argument_types) and length(argument_types) == arity,
       do: Enum.all?(argument_types, &CompilerTypeMatcher.supported?/1)

  defp arguments_supported?(_argument_types, _arity), do: false

  defp inferable_ids(inference_rules, true) do
    if Enum.all?(inference_rules, & &1.arguments_supported?) do
      inference_rules
      |> Enum.filter(&(MapSet.size(&1.output_ids) == 1))
      |> Enum.reduce(MapSet.new(), fn rule, ids -> MapSet.union(ids, rule.output_ids) end)
    else
      MapSet.new()
    end
  end

  defp inferable_ids(_inference_rules, false), do: MapSet.new()

  defp empty_decoded_export, do: %{return_alternatives: [], inference_rules: []}

  defp unwrap_dynamic({:dynamic, _, [type]}), do: type
  defp unwrap_dynamic(type), do: type

  defp flatten_union({:or, _, [left, right]}),
    do: flatten_union(left) ++ flatten_union(right)

  defp flatten_union(type), do: [type]

  defp finite_discriminant?({:__block__, _, [literal]}),
    do: is_atom(literal) or is_integer(literal) or is_binary(literal)

  defp finite_discriminant?({:{}, _, [discriminant | _fields]}),
    do: finite_discriminant?(discriminant)

  defp finite_discriminant?({:and, _, [left, right]}),
    do: finite_discriminant?(left) or finite_discriminant?(right)

  defp finite_discriminant?(_type), do: false
end
