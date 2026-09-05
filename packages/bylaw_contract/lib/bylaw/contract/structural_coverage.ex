defmodule Bylaw.Contract.StructuralCoverage do
  @moduledoc false

  alias Bylaw.Contract.FunctionSelection

  @shadow_modules for index <- 1..32, do: Module.concat(__MODULE__, "Shadow#{index}")
  @erlang_source_names %{
    :andalso => :and,
    :orelse => :or,
    :"=:=" => :===,
    :"=/=" => :!==,
    :"/=" => :!=,
    :"=<" => :<=
  }

  @spec load(modules :: list(module()), selection :: FunctionSelection.t()) :: map()
  def load(modules, selection \\ :all) do
    modules
    |> FunctionSelection.modules(selection)
    |> Enum.uniq()
    |> Enum.reduce(empty_result(), fn module, result ->
      case load_module(module, selection) do
        {:ok, loaded} -> merge_loaded(result, loaded)
        {:error, reason} -> add_unsupported(result, module, reason)
      end
    end)
    |> sort_result()
  end

  @spec start_shadow(classifiers :: list(map())) :: {:ok, module()} | {:error, String.t()}
  def start_shadow(classifiers) do
    :global.trans({__MODULE__, :shadow_pool}, fn ->
      do_start_shadow(classifiers)
    end)
  end

  defp do_start_shadow(classifiers) do
    with {:ok, shadow_module} <- available_shadow_module() do
      forms = shadow_forms(shadow_module, classifiers)

      with {:ok, ^shadow_module, binary} <- compile_forms(forms, shadow_module),
           {:module, ^shadow_module} <-
             :code.load_binary(shadow_module, ~c"bylaw_contract_structural_shadow", binary) do
        {:ok, shadow_module}
      else
        {:error, errors, warnings} ->
          {:error,
           "could not compile structural classifiers: #{format_compile_errors(errors, warnings)}"}

        {:error, reason} ->
          {:error, "could not load structural classifiers: #{inspect(reason)}"}

        other ->
          {:error, "could not load structural classifiers: #{inspect(other)}"}
      end
    end
  end

  @spec stop_shadow(shadow_module :: module() | nil) :: :ok
  def stop_shadow(nil), do: :ok
  def stop_shadow(shadow_module) when is_atom(shadow_module), do: unload_shadow(shadow_module)

  @doc false
  @spec classify(
          shadow_module :: module(),
          classifier :: map(),
          arguments :: list(term()),
          caller :: pid()
        ) :: {non_neg_integer() | :no_clause, list({boolean(), boolean()})}
  def classify(shadow_module, classifier, arguments, caller) do
    apply(shadow_module, classifier.classifier_function, [
      classifier.source_function,
      classifier.source_arity,
      arguments,
      caller
    ])
  end

  defp empty_result do
    %{
      clauses: [],
      arities: [],
      classifier_clauses: [],
      classifiers: [],
      modules: [],
      warnings: []
    }
  end

  defp load_module(module, selection) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         {^module, binary, _} <- :code.get_object_code(module),
         {:ok, {^module, chunks}} <-
           :beam_lib.chunks(binary, [:debug_info, :compile_info]),
         {:ok, definitions, unreachable} <-
           elixir_definitions(Keyword.fetch!(chunks, :debug_info)),
         {:ok, {^module, [{:abstract_code, abstract_code}]}} <-
           :beam_lib.chunks(binary, [:abstract_code]),
         {:ok, forms} <- abstract_forms(abstract_code),
         {:ok, loaded} <-
           extract_module(module, definitions, unreachable, forms, source_file(chunks), selection) do
      {:ok, loaded}
    else
      {:error, reason} ->
        {:error, reason}

      :error ->
        {:error, "compiled BEAM object code is unavailable"}

      {:error, _, reason} ->
        {:error, "could not read BEAM debug information: #{inspect(reason)}"}

      other ->
        {:error, "could not inspect compiled module: #{inspect(other)}"}
    end
  end

  defp elixir_definitions(
         {:debug_info_v1, :elixir_erl,
          {:elixir_v1, %{definitions: definitions, unreachable: unreachable}, _}}
       )
       when is_list(definitions) and is_list(unreachable),
       do: {:ok, definitions, MapSet.new(unreachable)}

  defp elixir_definitions(:no_debug_info), do: {:error, "Elixir debug information is absent"}

  defp elixir_definitions(_),
    do: {:error, "Elixir debug information is unavailable or unsupported"}

  defp abstract_forms({:raw_abstract_v1, forms}) when is_list(forms), do: {:ok, forms}
  defp abstract_forms(:no_abstract_code), do: {:error, "BEAM abstract code is absent"}
  defp abstract_forms(_), do: {:error, "BEAM abstract code is unavailable or unsupported"}

  defp extract_module(module, definitions, unreachable, forms, source_file, selection) do
    functions =
      Enum.reduce(forms, %{}, fn
        {:function, annotation, function, arity, clauses}, acc ->
          Map.put(acc, {function, arity}, {annotation, clauses})

        _, acc ->
          acc
      end)

    relevant_definitions =
      Enum.filter(definitions, fn {{function, arity}, _, _, _} = definition ->
        FunctionSelection.member?(selection, module, function, arity) and
          (authored_definition?(definition) or default_wrapper_definition?(definition))
      end)

    case Enum.reduce_while(
           relevant_definitions,
           {:ok, empty_result()},
           fn definition, {:ok, result} ->
             case extract_definition(module, definition, unreachable, functions, source_file) do
               {:ok, loaded} -> {:cont, {:ok, merge_loaded(result, loaded)}}
               {:error, reason} -> {:halt, {:error, reason}}
             end
           end
         ) do
      {:ok, result} ->
        {:ok,
         %{
           result
           | modules: [%{module: module, status: :supported}],
             warnings: []
         }}

      error ->
        error
    end
  end

  defp extract_definition(
         module,
         {{function, arity}, kind, definition_meta, source_clauses} = definition,
         unreachable,
         functions,
         source_file
       ) do
    default_wrapper? = default_wrapper_definition?(definition)

    case {Map.fetch(functions, {function, arity}), default_wrapper?} do
      {:error, true} ->
        {:ok, empty_result()}

      {{:ok, {_, abstract_clauses}}, _}
      when :erlang.length(abstract_clauses) == :erlang.length(source_clauses) ->
        if default_wrapper? do
          {:ok,
           %{
             empty_result()
             | arities: [
                 arity_entry(
                   module,
                   function,
                   arity,
                   kind,
                   definition_meta,
                   false,
                   true
                 )
               ]
           }}
        else
          clauses =
            abstract_clauses
            |> Enum.zip(source_clauses)
            |> Enum.with_index(1)
            |> Enum.map(fn {{{:clause, annotation, _, guards, _}, source_clause}, index} ->
              line = source_clause_line(source_clause, annotation)

              %{
                id: {module, function, arity, line, index},
                module: module,
                function: function,
                arity: arity,
                file: source_clause_file(source_clause, source_file),
                line: line,
                position: index,
                source: source_clause_label(kind, function, source_clause),
                visibility: visibility(kind),
                guarded?: Enum.any?(guards)
              }
            end)

          classifier_clauses =
            Enum.map(Enum.zip(clauses, abstract_clauses), fn {clause, abstract_clause} ->
              %{id: clause.id, module: module, function: function, clause: abstract_clause}
            end)

          {:ok,
           %{
             empty_result()
             | clauses: clauses,
               classifier_clauses: classifier_clauses,
               arities: [
                 arity_entry(
                   module,
                   function,
                   arity,
                   kind,
                   definition_meta,
                   true,
                   false
                 )
               ]
           }}
        end

      {{:ok, {_, abstract_clauses}}, _} ->
        {:error,
         "compiled clauses for #{inspect(module)}.#{function}/#{arity} do not match its Elixir debug definition " <>
           "(#{Enum.count(abstract_clauses)} compiled, #{Enum.count(source_clauses)} authored)"}

      {:error, false} ->
        if kind == :defp and MapSet.member?(unreachable, {function, arity}) do
          {:ok, empty_result()}
        else
          {:error, "compiled function #{inspect(module)}.#{function}/#{arity} is absent"}
        end
    end
  end

  defp authored_definition?({{_, _}, kind, meta, _})
       when kind in [:def, :defp],
       do: is_nil(Keyword.get(meta, :context))

  defp authored_definition?(_), do: false

  defp default_wrapper_definition?({{_, _}, kind, _, clauses})
       when kind in [:def, :defp] do
    Enum.any?(clauses) and
      Enum.all?(clauses, fn
        {_, _, _, {:super, body_meta, _}} ->
          Keyword.get(body_meta, :default) == true

        _ ->
          false
      end)
  end

  defp default_wrapper_definition?(_), do: false

  defp arity_entry(module, function, arity, kind, meta, authored?, default_wrapper?) do
    %{
      id: {module, function, arity},
      module: module,
      function: function,
      arity: arity,
      line: Keyword.get(meta, :line, 0),
      visibility: visibility(kind),
      authored?: authored?,
      default_wrapper?: default_wrapper?,
      declares_defaults?: authored? and Keyword.get(meta, :defaults, 0) > 0
    }
  end

  defp visibility(:def), do: :public
  defp visibility(:defp), do: :private

  defp source_clause_line({meta, _, _, _}, annotation) do
    Keyword.get(meta, :line, :erl_anno.line(annotation))
  end

  defp source_clause_file({meta, _, _, _}, module_source_file) do
    meta
    |> Keyword.get(:file, module_source_file)
    |> normalize_source_file()
  end

  defp source_file(chunks) do
    chunks
    |> Keyword.get(:compile_info, [])
    |> Keyword.get(:source)
    |> normalize_source_file()
  end

  defp normalize_source_file(file) when is_binary(file), do: file
  defp normalize_source_file(file) when is_list(file), do: List.to_string(file)
  defp normalize_source_file(_), do: nil

  defp source_clause_label(kind, function, {_, arguments, guards, _}) do
    head = {function, [], normalize_source_ast(arguments)}

    guarded_head =
      Enum.reduce(guards, head, fn guard, guarded_head ->
        {:when, [], [guarded_head, normalize_source_ast(guard)]}
      end)

    "#{kind} #{Macro.to_string(guarded_head)}"
  end

  defp normalize_source_ast(ast) do
    Macro.prewalk(ast, fn
      {{:., _, [:erlang, function]}, call_meta, arguments} when is_atom(function) ->
        {Map.get(@erlang_source_names, function, function), call_meta, arguments}

      node ->
        node
    end)
  end

  defp merge_loaded(result, loaded) do
    %{
      clauses: loaded.clauses ++ result.clauses,
      arities: loaded.arities ++ result.arities,
      classifier_clauses: loaded.classifier_clauses ++ result.classifier_clauses,
      classifiers: loaded.classifiers ++ result.classifiers,
      modules: loaded.modules ++ result.modules,
      warnings: loaded.warnings ++ result.warnings
    }
  end

  defp add_unsupported(result, module, reason) do
    %{
      result
      | modules: [%{module: module, status: :unsupported, reason: reason} | result.modules],
        warnings: [
          "structural coverage unsupported for #{inspect(module)}: #{reason}" | result.warnings
        ]
    }
  end

  defp sort_result(result) do
    classifier_clauses =
      Enum.sort_by(result.classifier_clauses, fn entry ->
        {entry.module, entry.function, elem(entry.id, 2), elem(entry.id, 4)}
      end)

    classifiers_by_mfa =
      classifier_clauses
      |> Enum.group_by(&{&1.module, &1.function, elem(&1.id, 2)})
      |> Enum.sort_by(fn {mfa, _} -> mfa end)
      |> Enum.map(fn {mfa, clauses} ->
        %{mfa: mfa, clauses: clauses}
      end)

    classifiers =
      classifiers_by_mfa
      |> Enum.group_by(fn %{mfa: {module, _, _}} -> module end)
      |> Enum.sort_by(fn {module, _} -> module end)
      |> Enum.map(fn {module, mfa_classifiers} ->
        %{
          module: module,
          classifier_function: module,
          mfa_classifiers: mfa_classifiers
        }
      end)

    %{
      result
      | clauses:
          Enum.sort_by(result.clauses, &{&1.module, &1.function, &1.arity, &1.line, &1.position}),
        arities: Enum.sort_by(result.arities, &{&1.module, &1.function, &1.arity}),
        classifier_clauses: [],
        classifiers: classifiers,
        modules: Enum.sort_by(result.modules, & &1.module),
        warnings: Enum.reverse(result.warnings)
    }
  end

  defp shadow_forms(shadow_module, classifiers) do
    exports = Enum.map(classifiers, &{&1.classifier_function, 4})

    [
      {:attribute, 0, :module, shadow_module},
      {:attribute, 0, :export, exports}
      | Enum.map(classifiers, &classifier_form/1)
    ]
  end

  defp classifier_form(classifier) do
    clauses = Enum.map(classifier.mfa_classifiers, &classifier_mfa_clause/1)
    {:function, 0, classifier.classifier_function, 4, clauses}
  end

  defp classifier_mfa_clause(%{mfa: {_, function, arity}, clauses: clauses}) do
    caller = caller_variable(clauses)
    clauses = Enum.map(clauses, &replace_caller_guards(&1, caller))
    arguments = {:var, 0, :_BylawContractArguments}
    selected = scoped_case(arguments, selection_clauses(clauses))

    outcomes = Enum.map(clauses, &outcome_case(arguments, &1.clause))

    body = {:tuple, 0, [selected, abstract_list(outcomes)]}

    {:clause, 0, [:erl_parse.abstract(function), :erl_parse.abstract(arity), arguments, caller],
     [], [body]}
  end

  defp caller_variable(clauses) do
    used =
      Enum.reduce(clauses, MapSet.new(), fn entry, names ->
        {:clause, _, patterns, guards, _} = entry.clause
        variable_names({patterns, guards}, names)
      end)

    name =
      Stream.iterate(0, &(&1 + 1))
      |> Enum.find_value(fn index ->
        # Compiler names are reused; their count is bounded by conflicting source variables.
        # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
        name = String.to_atom("_BylawContractCaller#{index}")

        if not MapSet.member?(used, name) do
          name
        end
      end)

    {:var, 0, name}
  end

  defp variable_names({:var, _, name}, names), do: MapSet.put(names, name)

  defp variable_names(term, names) when is_tuple(term),
    do: variable_names(Tuple.to_list(term), names)

  defp variable_names(terms, names) when is_list(terms),
    do: Enum.reduce(terms, names, &variable_names/2)

  defp variable_names(_, names), do: names

  defp replace_caller_guards(entry, caller) do
    {:clause, annotation, patterns, guards, body} = entry.clause
    %{entry | clause: {:clause, annotation, patterns, replace_self(guards, caller), body}}
  end

  defp replace_self({:call, _, {:remote, _, {:atom, _, :erlang}, {:atom, _, :self}}, []}, caller),
    do: caller

  defp replace_self({:call, _, {:atom, _, :self}, []}, caller), do: caller

  defp replace_self(term, caller) when is_tuple(term),
    do: term |> Tuple.to_list() |> Enum.map(&replace_self(&1, caller)) |> List.to_tuple()

  defp replace_self(terms, caller) when is_list(terms),
    do: Enum.map(terms, &replace_self(&1, caller))

  defp replace_self(term, _caller), do: term

  defp selection_clauses(classifier_clauses) do
    clauses =
      Enum.map(classifier_clauses, fn %{
                                        id: id,
                                        clause: {:clause, annotation, patterns, guards, _}
                                      } ->
        {:clause, annotation, [list_pattern(patterns)], guards,
         [:erl_parse.abstract(elem(id, 4))]}
      end)

    clauses ++ [{:clause, 0, [{:var, 0, :_}], [], [{:atom, 0, :no_clause}]}]
  end

  defp outcome_case(arguments, {:clause, annotation, patterns, guards, _}) do
    matched =
      {:clause, annotation, [list_pattern(patterns)], guards, [:erl_parse.abstract({true, true})]}

    rejected =
      if Enum.empty?(guards) do
        []
      else
        [
          {:clause, annotation, [list_pattern(patterns)], [],
           [:erl_parse.abstract({true, false})]}
        ]
      end

    missed = {:clause, 0, [{:var, 0, :_}], [], [:erl_parse.abstract({false, false})]}
    scoped_case(arguments, [matched] ++ rejected ++ [missed])
  end

  defp scoped_case(arguments, clauses) do
    scoped_arguments = {:var, 0, :_BylawContractScopedArguments}
    case_expression = {:case, 0, scoped_arguments, clauses}
    function = {:fun, 0, {:clauses, [{:clause, 0, [scoped_arguments], [], [case_expression]}]}}

    {:call, 0, function, [arguments]}
  end

  defp list_pattern(patterns) do
    Enum.reduce(Enum.reverse(patterns), {nil, 0}, fn pattern, tail ->
      {:cons, 0, pattern, tail}
    end)
  end

  defp abstract_list(elements) do
    Enum.reduce(Enum.reverse(elements), {nil, 0}, fn element, tail ->
      {:cons, 0, element, tail}
    end)
  end

  defp compile_forms(forms, shadow_module) do
    case :compile.forms(forms, [:return_errors, :return_warnings]) do
      {:ok, ^shadow_module, binary} -> {:ok, shadow_module, binary}
      {:ok, ^shadow_module, binary, _} -> {:ok, shadow_module, binary}
      {:error, errors, warnings} -> {:error, errors, warnings}
    end
  end

  defp format_compile_errors(errors, warnings) do
    inspect(%{errors: errors, warnings: warnings}, limit: :infinity)
  end

  defp available_shadow_module do
    case Enum.find(@shadow_modules, &(:code.is_loaded(&1) == false)) do
      nil -> {:error, "all temporary structural classifier slots are in use"}
      shadow_module -> {:ok, shadow_module}
    end
  end

  defp unload_shadow(shadow_module) do
    :code.delete(shadow_module)
    :code.purge(shadow_module)
    :ok
  end
end
