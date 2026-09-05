defmodule Bylaw.Contract.CompilerInference do
  @moduledoc false

  alias Bylaw.Contract.FunctionSelection

  alias Bylaw.Contract.CompilerInference.Elixir120

  @module_timeout 100

  @doc false
  @spec load(modules :: list(module()), selection :: FunctionSelection.t()) :: map()
  def load(modules, selection \\ :all) do
    modules
    |> FunctionSelection.modules(selection)
    |> Enum.uniq()
    |> Enum.reduce(empty_result(), fn module, result ->
      load_module_isolated(module, result, selection)
    end)
    |> sort_result()
  end

  defp empty_result do
    %{
      return_alternatives: [],
      inference_rules: [],
      modules: [],
      warnings: [],
      authored_mfas: MapSet.new(),
      unknown_authorship_modules: MapSet.new()
    }
  end

  defp load_module_isolated(module, result, selection) do
    case isolated(fn -> load_module(module, empty_result(), selection) end) do
      {:ok, module_result} -> merge_results(result, module_result)
      {:error, reason} -> unsupported(result, module, reason)
    end
  end

  defp load_module(module, result, selection) do
    case read_module(module) do
      {:ok, checker_version, exports, authorship} ->
        exports =
          Enum.filter(exports, fn {{function, arity}, _} ->
            FunctionSelection.member?(selection, module, function, arity)
          end)

        case Elixir120.return_alternatives(module, exports) do
          {:ok, decoded} ->
            {decoded, authorship} =
              if protocol_implementation?(module) do
                {%{return_alternatives: [], inference_rules: []}, {:known, MapSet.new()}}
              else
                {decoded, authorship}
              end

            result = %{
              result
              | return_alternatives: decoded.return_alternatives ++ result.return_alternatives,
                inference_rules: decoded.inference_rules ++ result.inference_rules,
                modules: [
                  %{module: module, status: :supported, checker_version: checker_version}
                  | result.modules
                ]
            }

            merge_authorship(result, module, authorship)

          {:error, reason} ->
            unsupported(result, module, reason)
        end

      {:error, reason} ->
        unsupported(result, module, reason)
    end
  end

  defp isolated(function) do
    parent = self()
    request = make_ref()

    {process, monitor} =
      spawn_monitor(fn ->
        send(parent, {request, function.()})
      end)

    receive do
      {^request, result} ->
        Process.demonitor(monitor, [:flush])
        {:ok, result}

      {:DOWN, ^monitor, :process, ^process, reason} ->
        {:error, "compiler inference inspection failed: #{inspect(reason)}"}
    after
      @module_timeout ->
        Process.exit(process, :kill)

        receive do
          {:DOWN, ^monitor, :process, ^process, _reason} -> :ok
        end

        receive do
          {^request, _result} -> :ok
        after
          0 -> :ok
        end

        {:error, "compiler inference inspection exceeded #{@module_timeout}ms"}
    end
  end

  defp merge_results(result, module_result) do
    %{
      return_alternatives: module_result.return_alternatives ++ result.return_alternatives,
      inference_rules: module_result.inference_rules ++ result.inference_rules,
      modules: module_result.modules ++ result.modules,
      warnings: module_result.warnings ++ result.warnings,
      authored_mfas: MapSet.union(result.authored_mfas, module_result.authored_mfas),
      unknown_authorship_modules:
        MapSet.union(
          result.unknown_authorship_modules,
          module_result.unknown_authorship_modules
        )
    }
  end

  defp unsupported(result, module, reason) do
    %{
      result
      | modules: [%{module: module, status: :unsupported, reason: reason} | result.modules],
        warnings: [
          "compiler inference unsupported for #{inspect(module)}: #{reason}"
          | result.warnings
        ]
    }
  end

  defp read_module(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         {^module, binary, _} <- :code.get_object_code(module),
         {:ok, {^module, chunks}} <- :beam_lib.chunks(binary, [~c"ExCk", :debug_info]),
         chunk when is_binary(chunk) <- List.keyfind(chunks, ~c"ExCk", 0, {nil, nil}) |> elem(1),
         {:ok, checker_version, exports} <- decode_chunk(chunk),
         :ok <- inferred_signatures_present(exports) do
      debug_info = List.keyfind(chunks, :debug_info, 0, {nil, nil}) |> elem(1)
      {:ok, checker_version, exports, authored_mfas(module, debug_info)}
    else
      {:error, reason} -> {:error, reason}
      :error -> {:error, "compiled BEAM object code is unavailable"}
      {:error, _, reason} -> {:error, "could not read the BEAM checker chunk: #{inspect(reason)}"}
      other -> {:error, "could not inspect compiler inference: #{inspect(other)}"}
    end
  end

  defp authored_mfas(
         module,
         {:debug_info_v1, :elixir_erl, {:elixir_v1, %{definitions: definitions}, _}}
       )
       when is_list(definitions) do
    mfas =
      definitions
      |> Enum.filter(&authored_definition?/1)
      |> MapSet.new(fn {{function, arity}, _kind, _meta, _clauses} ->
        {module, function, arity}
      end)

    {:known, mfas}
  end

  defp authored_mfas(_module, :no_debug_info),
    do: {:unknown, "Elixir debug information is absent"}

  defp authored_mfas(_module, {:debug_info_v1, :elixir_erl, :none}),
    do: {:unknown, "Elixir debug information is absent"}

  defp authored_mfas(_module, _debug_info),
    do: {:unknown, "Elixir debug information is unavailable or unsupported"}

  defp authored_definition?({{_, _}, kind, meta, _})
       when kind in [:def, :defp],
       do: is_nil(Keyword.get(meta, :context))

  defp authored_definition?(_), do: false

  defp protocol_implementation?(module) do
    module.__info__(:attributes)
    |> Keyword.has_key?(:__impl__)
  rescue
    UndefinedFunctionError -> false
  end

  defp merge_authorship(result, _module, {:known, mfas}) do
    %{result | authored_mfas: MapSet.union(result.authored_mfas, mfas)}
  end

  defp merge_authorship(result, module, {:unknown, reason}) do
    %{
      result
      | unknown_authorship_modules: MapSet.put(result.unknown_authorship_modules, module),
        warnings: [
          "compiler call inference unsupported for #{inspect(module)}: #{reason}"
          | result.warnings
        ]
    }
  end

  defp decode_chunk(chunk) do
    case :erlang.binary_to_term(chunk, [:safe]) do
      {checker_version, %{exports: exports}} when is_list(exports) ->
        if checker_version == Elixir120.checker_version() do
          {:ok, checker_version, exports}
        else
          {:error, "unsupported Elixir checker version #{inspect(checker_version)}"}
        end

      {checker_version, _contents} ->
        {:error, "unsupported Elixir checker version #{inspect(checker_version)}"}

      _ ->
        {:error, "invalid Elixir checker chunk"}
    end
  rescue
    ArgumentError -> {:error, "Elixir checker chunk was rejected by safe term decoding"}
  end

  defp inferred_signatures_present([]), do: :ok

  defp inferred_signatures_present(exports) do
    if Enum.any?(exports, fn
         {_function, %{sig: {:infer, _, _}}} -> true
         _ -> false
       end) do
      :ok
    else
      {:error, "compiler-inferred signatures are absent"}
    end
  end

  defp sort_result(result) do
    %{
      result
      | return_alternatives:
          Enum.sort_by(result.return_alternatives, &{&1.module, &1.function, &1.arity, &1.label}),
        inference_rules:
          Enum.sort_by(result.inference_rules, &{&1.module, &1.function, &1.arity, &1.index}),
        modules: Enum.sort_by(result.modules, & &1.module),
        warnings: Enum.reverse(result.warnings)
    }
  end
end
