defmodule Bylaw.Contract.Check.ElixirCompiler do
  @moduledoc """
  Observes return alternatives inferred by the Elixir compiler.

  The check maps unambiguous input-to-return rules in the compiler's private
  checker chunk to narrowly injected clause counters. It does not enable VM
  tracing or inspect returned values.

  Earlier checks remain authoritative. Compiler-inferred alternatives are
  omitted when an earlier check claims return alternatives for the same
  function.
  """

  @behaviour Bylaw.Contract.Check

  alias Bylaw.Contract.CompilerClauseMapper
  alias Bylaw.Contract.CompilerInference
  alias Bylaw.Contract.CompilerObserver

  @default_max_functions 10

  @impl Bylaw.Contract.Check
  def init(modules, opts, context) do
    with {:ok, opts} <- Keyword.validate(opts, max_functions: @default_max_functions),
         {:ok, max_functions} <-
           validate_limit(:max_functions, Keyword.fetch!(opts, :max_functions)) do
      init_with_limit(modules, context, max_functions)
    else
      {:error, invalid} when is_list(invalid) ->
        {:error, "unsupported Elixir compiler check options: #{inspect(invalid)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp init_with_limit(modules, context, max_functions) do
    loaded = CompilerInference.load(modules, Map.get(context, :only, :all))

    return_alternatives =
      Enum.reject(loaded.return_alternatives, fn alternative ->
        MapSet.member?(context.claims, {:return_alternatives, mfa(alternative)})
      end)

    {authored_alternatives, unknown_authorship_alternatives} =
      Enum.reduce(return_alternatives, {[], []}, fn alternative, {authored, unknown} ->
        cond do
          MapSet.member?(loaded.authored_mfas, mfa(alternative)) ->
            {[alternative | authored], unknown}

          MapSet.member?(loaded.unknown_authorship_modules, alternative.module) ->
            {authored, [alternative | unknown]}

          true ->
            {authored, unknown}
        end
      end)

    authored_alternatives = Enum.reverse(authored_alternatives)
    unknown_authorship_alternatives = Enum.reverse(unknown_authorship_alternatives)
    inferable_alternatives = Enum.filter(authored_alternatives, & &1.inferable?)

    {selected_alternatives_by_mfa, omitted_alternatives} =
      inferable_alternatives
      |> Enum.group_by(&mfa/1)
      |> limit_functions(max_functions)

    selected_mfas = selected_alternatives_by_mfa |> Map.keys() |> MapSet.new()

    selected_rules_by_mfa =
      loaded.inference_rules
      |> Enum.filter(&MapSet.member?(selected_mfas, mfa(&1)))
      |> Enum.group_by(&mfa/1)

    observer_token = CompilerObserver.start()

    {instrumented_modules, mapped_rules, instrumentation_warnings} =
      instrument_modules(selected_rules_by_mfa, observer_token)

    mapped_mfas = MapSet.new(mapped_rules, &mfa/1)

    alternatives_by_mfa =
      Map.filter(selected_alternatives_by_mfa, fn {mfa, _alternatives} ->
        MapSet.member?(mapped_mfas, mfa)
      end)

    assessable_mfas = alternatives_by_mfa |> Map.keys() |> MapSet.new()

    rules_by_mfa = Enum.group_by(mapped_rules, &mfa/1)

    unassessable_selected =
      selected_alternatives_by_mfa
      |> Enum.reject(fn {mfa, _alternatives} -> MapSet.member?(assessable_mfas, mfa) end)
      |> Enum.flat_map(&elem(&1, 1))

    initial_unknown =
      authored_alternatives
      |> Enum.reject(& &1.inferable?)
      |> Kernel.++(unknown_authorship_alternatives)
      |> Kernel.++(omitted_alternatives)
      |> Kernel.++(unassessable_selected)
      |> MapSet.new(& &1.id)

    state = %{
      compiler_return_alternatives: authored_alternatives ++ unknown_authorship_alternatives,
      compiler_modules: loaded.modules,
      compiler_warnings:
        loaded.warnings ++
          function_limit_warnings(omitted_alternatives, max_functions) ++
          instrumentation_warnings,
      alternatives_by_mfa: alternatives_by_mfa,
      rules_by_mfa: rules_by_mfa,
      instrumented_modules: instrumented_modules,
      observer_token: observer_token,
      unknown: initial_unknown
    }

    claims = MapSet.new(authored_alternatives, &{:return_alternatives, mfa(&1)})

    {:ok, state, %{calls: MapSet.new(), returns: MapSet.new(), claims: claims}}
  end

  @impl Bylaw.Contract.Check
  def observe(_event, state), do: state

  @impl Bylaw.Contract.Check
  def coverage(state) do
    clause_calls = CompilerObserver.counts(state.observer_token)

    compiler_calls =
      Map.new(state.rules_by_mfa, fn {mfa, rules} ->
        calls = Enum.sum(Enum.map(rules, &Map.get(clause_calls, {mfa, &1.index}, 0)))
        {mfa, calls}
      end)
      |> Map.reject(fn {_mfa, calls} -> calls == 0 end)

    hits =
      state.rules_by_mfa
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.reduce(%{}, fn rule, hits ->
        calls = Map.get(clause_calls, {mfa(rule), rule.index}, 0)

        if calls > 0 and MapSet.size(rule.output_ids) == 1 do
          [id] = MapSet.to_list(rule.output_ids)
          Map.put(hits, id, 1)
        else
          hits
        end
      end)

    unknown =
      state.unknown
      |> MapSet.union(unobserved_function_alternatives(state, compiler_calls))

    state
    |> Map.take([
      :compiler_return_alternatives,
      :compiler_modules,
      :compiler_warnings
    ])
    |> Map.merge(%{compiler_calls: compiler_calls, hits: hits, unknown: unknown})
  end

  @impl Bylaw.Contract.Check
  def terminate(state) do
    Enum.each(state.instrumented_modules, &restore_module/1)
    CompilerObserver.stop(state.observer_token)
  end

  defp instrument_modules(rules_by_mfa, observer_token) do
    rules_by_module =
      rules_by_mfa
      |> Enum.flat_map(&elem(&1, 1))
      |> Enum.group_by(& &1.module)

    {instrumented, mapped, warnings} =
      Enum.reduce(rules_by_module, {%{}, [], []}, fn {module, rules},
                                                     {instrumented, mapped, warnings} ->
        case instrument_module(module, rules, observer_token) do
          {:ok, original, source_rules} ->
            unmapped =
              MapSet.difference(MapSet.new(rules, &mfa/1), MapSet.new(source_rules, &mfa/1))

            mapping_warnings =
              Enum.map(unmapped, fn {module, function, arity} ->
                "compiler source clause mapping unsupported for #{inspect(module)}.#{function}/#{arity}"
              end)

            {Map.put(instrumented, module, original), source_rules ++ mapped,
             mapping_warnings ++ warnings}

          {:error, reason} ->
            warning =
              "compiler clause instrumentation unsupported for #{inspect(module)}: #{reason}"

            {instrumented, mapped, [warning | warnings]}
        end
      end)

    {instrumented, mapped, Enum.reverse(warnings)}
  end

  defp instrument_module(module, _rules, _observer_token)
       when module in [
              __MODULE__,
              Bylaw.Contract.Tracer,
              Bylaw.Contract.TraceWorker,
              CompilerObserver
            ],
       do: {:error, "observer runtime modules cannot be hot-reloaded during observation"}

  defp instrument_module(module, rules, observer_token) do
    with {^module, binary, filename} <- :code.get_object_code(module),
         {:ok, {^module, [{:abstract_code, {:raw_abstract_v1, forms}}]}} <-
           :beam_lib.chunks(binary, [:abstract_code]),
         source_rules <- CompilerClauseMapper.map(forms, module, rules),
         false <- Enum.empty?(source_rules),
         instrumented_forms <- inject_counters(forms, module, source_rules, observer_token),
         {:ok, instrumented_binary} <- compile_instrumented(module, instrumented_forms),
         {:module, ^module} <- load_instrumented(module, instrumented_binary) do
      {:ok, %{module: module, binary: binary, filename: filename}, source_rules}
    else
      true -> {:error, "no unambiguous source clause mappings"}
      :error -> {:error, "compiled BEAM object code is unavailable"}
      {:error, reason} -> {:error, inspect(reason)}
      other -> {:error, inspect(other)}
    end
  rescue
    error in [ArgumentError, ErlangError] -> {:error, Exception.message(error)}
  end

  defp inject_counters(forms, module, rules, observer_token) do
    clause_indexes =
      Map.new(Enum.group_by(rules, &{&1.function, &1.arity}), fn {function, function_rules} ->
        {function, MapSet.new(function_rules, & &1.index)}
      end)

    Enum.map(forms, fn
      {:function, annotation, function, arity, clauses} = form ->
        case Map.fetch(clause_indexes, {function, arity}) do
          {:ok, indexes} ->
            clauses =
              clauses
              |> Enum.with_index(1)
              |> Enum.map(fn
                {{:clause, clause_annotation, arguments, guards, body}, index} ->
                  if MapSet.member?(indexes, index) do
                    hit =
                      hit_form(
                        clause_annotation,
                        observer_token,
                        {module, function, arity},
                        index
                      )

                    {:clause, clause_annotation, arguments, guards, [hit | body]}
                  else
                    {:clause, clause_annotation, arguments, guards, body}
                  end
              end)

            {:function, annotation, function, arity, clauses}

          :error ->
            form
        end

      form ->
        form
    end)
  end

  defp hit_form(annotation, observer_token, mfa, clause) do
    {:call, annotation,
     {:remote, annotation, {:atom, annotation, CompilerObserver}, {:atom, annotation, :hit}},
     [
       {:integer, annotation, observer_token},
       :erl_parse.abstract(mfa),
       {:integer, annotation, clause}
     ]}
  end

  defp compile_instrumented(module, forms) do
    case :compile.forms(forms, [:return_errors, :return_warnings, :debug_info]) do
      {:ok, ^module, binary} -> {:ok, binary}
      {:ok, ^module, binary, _warnings} -> {:ok, binary}
      {:error, errors, _warnings} -> {:error, {:compile_errors, errors}}
    end
  end

  defp load_instrumented(module, binary) do
    :code.purge(module)
    :code.load_binary(module, ~c"bylaw-compiler-observer", binary)
  end

  defp restore_module({_module, original}), do: restore_module(original)

  defp restore_module(%{module: module, binary: binary, filename: filename}) do
    :code.purge(module)
    {:module, ^module} = :code.load_binary(module, filename, binary)
    :code.purge(module)
    :ok
  end

  defp function_limit_warnings([], _max_functions), do: []

  defp function_limit_warnings(omitted, max_functions) do
    [
      "compiler clause instrumentation reached max_functions=#{max_functions}; " <>
        "#{Enum.count(omitted)} alternatives are unassessable"
    ]
  end

  defp validate_limit(_option, :infinity), do: {:ok, :infinity}

  defp validate_limit(_option, limit) when is_integer(limit) and limit > 0,
    do: {:ok, limit}

  defp validate_limit(option, limit) do
    {:error,
     "expected #{inspect(option)} to be a positive integer or :infinity, got: #{inspect(limit)}"}
  end

  defp limit_functions(alternatives_by_mfa, :infinity), do: {alternatives_by_mfa, []}

  defp limit_functions(alternatives_by_mfa, max_functions) do
    {selected, omitted} =
      alternatives_by_mfa
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.split(max_functions)

    {Map.new(selected), Enum.flat_map(omitted, &elem(&1, 1))}
  end

  defp unobserved_function_alternatives(state, compiler_calls) do
    state.alternatives_by_mfa
    |> Enum.reject(fn {mfa, _alternatives} -> Map.has_key?(compiler_calls, mfa) end)
    |> Enum.flat_map(&elem(&1, 1))
    |> MapSet.new(& &1.id)
  end

  defp mfa(target), do: {target.module, target.function, target.arity}
end
