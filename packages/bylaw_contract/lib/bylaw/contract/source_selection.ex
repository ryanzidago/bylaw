defmodule Bylaw.Contract.SourceSelection do
  @moduledoc """
  Maps explicit before/after Elixir source files to changed authored functions.

  This is a source comparison, not transitive semantic impact analysis. It does
  not read files, invoke Git, compile source, or evaluate expressions. Pass maps
  of source paths to their contents. Successful selection contains current
  authored functions and their default arities; deleted functions have no
  current observation target. Like Elixir's parser, this API creates atoms for
  identifiers and is intended for trusted project source.

  Direct alias-named Elixir modules and definitions are supported. Changes to
  shared module context return unresolved reasons. Conditional/generated definitions, custom
  macro setup, dynamic modules, and location-sensitive forms are unresolved,
  including when their source text is unchanged. Quoted code and compile-time
  unquote forms are unresolved because expansion can change definitions or
  locations. An error never carries a partial selection that could be mistaken for assessed empty scope.
  """

  @type files :: %{String.t() => String.t()}
  @type reason :: %{
          required(:code) => atom(),
          optional(:module) => module(),
          optional(:path) => String.t(),
          optional(:detail) => String.t()
        }

  @doc "Returns changed current MFAs, or explicit reasons why the supplied source cannot be mapped."
  @spec select(before_files :: files(), after_files :: files()) ::
          {:ok, MapSet.t({module(), atom(), arity()})} | {:error, list(reason())}
  def select(before_files, after_files) do
    with {:ok, before} <- inventory(before_files),
         {:ok, current} <- inventory(after_files) do
      context_errors =
        (Map.keys(before.contexts) ++ Map.keys(current.contexts))
        |> Enum.uniq()
        |> Enum.filter(&(Map.get(before.contexts, &1, []) != Map.get(current.contexts, &1, [])))
        |> Enum.map(&%{code: :unsupported_module_context, module: &1})

      if Enum.empty?(context_errors) do
        selected =
          current.functions
          |> Enum.reject(fn {mfa, entry} ->
            case Map.get(before.functions, mfa) do
              nil -> false
              old -> old.fingerprint == entry.fingerprint
            end
          end)
          |> Enum.flat_map(fn {{module, function, arity}, entry} ->
            Enum.map((arity - entry.defaults)..arity, &{module, function, &1})
          end)
          |> MapSet.new()

        {:ok, selected}
      else
        {:error, context_errors}
      end
    end
  end

  defp inventory(files) do
    Enum.reduce_while(Enum.sort(files), {:ok, %{functions: %{}, contexts: %{}}}, fn {path, source},
                                                                                    {:ok, state} ->
      with {:ok, ast} <- Code.string_to_quoted(source, file: path, emit_warnings: false),
           :ok <- location_independent(ast, path),
           {:ok, next} <- modules(expressions(ast), nil, state),
           :ok <- no_outer_context(next),
           :ok <- unquoted_source(ast, path) do
        {:cont, {:ok, next}}
      else
        {:error, reasons} when is_list(reasons) ->
          {:halt, {:error, reasons}}

        {:error, reason} ->
          {:halt, {:error, [%{code: :parse_error, path: path, detail: inspect(reason)}]}}
      end
    end)
  end

  defp modules([], _parent, state), do: {:ok, state}

  defp modules([{:defmodule, _, [{:__aliases__, _, parts}, [do: body]]} | rest], parent, state) do
    with {:ok, module} <- module_name(parts, parent),
         :ok <- no_outer_context(state),
         {:ok, state} <- module_body(module, expressions(body), state),
         {:ok, state} <- modules(rest, parent, state),
         do: {:ok, state}
  end

  defp modules([{:defmodule, _, _} | _], _parent, _state),
    do: {:error, [%{code: :dynamic_module}]}

  defp modules([other | rest], parent, state) do
    context =
      Map.update(state.contexts, :top_level, [normalize(other)], &(&1 ++ [normalize(other)]))

    modules(rest, parent, %{state | contexts: context})
  end

  defp module_name(parts, parent) do
    if Enum.any?(parts) and Enum.all?(parts, &is_atom/1) do
      parts =
        if parent && hd(parts) != Elixir do
          [parent | parts]
        else
          parts
        end

      # Static names from trusted parsed source must also work before compilation.
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      {:ok, Module.concat(parts)}
    else
      {:error, [%{code: :dynamic_module}]}
    end
  end

  defp module_body(module, forms, state) do
    if Map.has_key?(state.contexts, module) do
      {:error, [%{code: :duplicate_module, module: module}]}
    else
      {nested, local} = Enum.split_with(forms, &match?({:defmodule, _, _}, &1))

      inherited = Map.get(state, :inherited, [])

      {definitions, contextual_specs, _prefix} =
        Enum.reduce(forms, {[], [], inherited}, fn form, {definitions, specs, prefix} ->
          cond do
            match?({:defmodule, _, _}, form) ->
              {:defmodule, _, [name | _]} = form
              {definitions, specs, prefix ++ [{:nested_definition, name}]}

            match?({kind, _, _} when kind in [:def, :defp], form) ->
              {definitions ++ [{form, prefix}], specs, prefix}

            match?({:@, _, [{:spec, _, _}]}, form) ->
              {definitions, specs ++ [{form, prefix}], prefix}

            match?({:@, _, [{kind, _, _}]} when kind in [:doc, :moduledoc, :typedoc], form) ->
              {definitions, specs, prefix}

            true ->
              {definitions, specs, prefix ++ [form]}
          end
        end)

      other = Enum.reject(local, &match?({kind, _, _} when kind in [:def, :defp], &1))

      {_specs, context} = Enum.split_with(other, &match?({:@, _, [{:spec, _, _}]}, &1))

      context =
        Enum.reject(
          context,
          &match?({:@, _, [{kind, _, _}]} when kind in [:doc, :moduledoc, :typedoc], &1)
        )

      state = put_in(state.contexts[module], normalize(context))

      with :ok <- supported_documentation(module, forms),
           :ok <- supported_context(module, context),
           :ok <- no_nested_context(nested, context),
           {:ok, state} <- functions(module, definitions, contextual_specs, state),
           {:ok, state} <- nested_modules(module, forms, state) do
        {:ok, state}
      end
    end
  end

  defp nested_modules(parent, forms, state) do
    inherited = Map.get(state, :inherited, [])

    Enum.reduce_while(forms, {:ok, state, inherited}, fn
      {:defmodule, _, [name, _]} = form, {:ok, state, prefix} ->
        case modules([form], parent, Map.put(state, :inherited, prefix)) do
          {:ok, next} ->
            {:cont,
             {:ok, Map.put(next, :inherited, inherited), prefix ++ [{:nested_definition, name}]}}

          error ->
            {:halt, error}
        end

      _, acc ->
        {:cont, acc}
    end)
    |> case do
      {:ok, state, _} -> {:ok, state}
      error -> error
    end
  end

  defp supported_documentation(module, forms) do
    supported? =
      Enum.all?(forms, fn
        {:@, _, [{kind, _, [value]}]} when kind in [:doc, :moduledoc, :typedoc] ->
          Macro.quoted_literal?(value)

        _ ->
          true
      end)

    if supported? do
      :ok
    else
      {:error, [%{code: :unsupported_definition_context, module: module}]}
    end
  end

  defp supported_context(module, forms) do
    if Enum.all?(forms, &supported_context_form?/1) do
      :ok
    else
      {:error, [%{code: :unsupported_definition_context, module: module}]}
    end
  end

  defp supported_context_form?({:alias, _, [{:__aliases__, _, _}]}), do: true

  defp supported_context_form?({:alias, _, [{:__aliases__, _, _}, [as: {:__aliases__, _, _}]]}),
    do: true

  defp supported_context_form?({:@, _, [{kind, _, [_]}]}) when kind in [:type, :typep, :opaque],
    do: true

  defp supported_context_form?({:@, _, [{name, _, [value]}]})
       when name not in [
              :before_compile,
              :after_compile,
              :after_verify,
              :on_definition,
              :on_load,
              :compile
            ],
       do: Macro.quoted_literal?(value)

  defp supported_context_form?(_), do: false

  defp no_outer_context(state) do
    if Enum.any?(Map.get(state.contexts, :top_level, [])) do
      {:error, [%{code: :unsupported_outer_context}]}
    else
      :ok
    end
  end

  defp no_nested_context(nested, context) do
    if Enum.any?(nested) and Enum.any?(context) do
      {:error, [%{code: :unsupported_nested_context}]}
    else
      :ok
    end
  end

  defp functions(module, definitions, specs, state) do
    Enum.reduce_while(definitions, {:ok, state}, fn {{_, _, [head | _]} = definition, prefix},
                                                    {:ok, state} ->
      case signature(head) do
        {name, args} when is_atom(name) and is_list(args) ->
          arity = Enum.count(args)
          key = {module, name, arity}

          defaults =
            definitions
            |> Enum.map(fn {{_, _, [other_head | _]}, _} ->
              case signature(other_head) do
                {^name, other_args} when length(other_args) == arity ->
                  Enum.count(other_args, &match?({:\\, _, _}, &1))

                _ ->
                  0
              end
            end)
            |> Enum.max(fn -> 0 end)

          own_specs =
            Enum.filter(specs, fn spec ->
              case spec_signature(elem(spec, 0)) do
                {^name, spec_arity} -> spec_arity in (arity - defaults)..arity
                _ -> false
              end
            end)

          definition = {definition, prefix}
          initial = %{fingerprint: {[], normalize(own_specs)}, defaults: 0}

          state =
            update_in(
              state.functions,
              &Map.update(&1, key, add_definition(initial, definition, defaults), fn entry ->
                add_definition(entry, definition, defaults)
              end)
            )

          {:cont, {:ok, state}}

        _ ->
          {:halt, {:error, [%{code: :dynamic_function, module: module}]}}
      end
    end)
  end

  defp add_definition(entry, definition, defaults) do
    {clauses, specs} = entry.fingerprint

    %{
      entry
      | fingerprint: {clauses ++ [normalize(definition)], specs},
        defaults: max(entry.defaults, defaults)
    }
  end

  defp signature({name, _, _}) when name in [:unquote, :unquote_splicing], do: :unsupported
  defp signature({:when, _, [head | _]}), do: signature(head)
  defp signature({name, _, nil}) when is_atom(name), do: {name, []}
  defp signature({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp signature(_), do: :unsupported
  defp spec_signature({:@, _, [{:spec, _, [spec]}]}), do: spec_head(spec)
  defp spec_head({:when, _, [spec | _]}), do: spec_head(spec)

  defp spec_head({:"::", _, [head, _]}) do
    case signature(head) do
      {name, args} -> {name, Enum.count(args)}
      _ -> :unsupported
    end
  end

  defp spec_head(_), do: :unsupported

  defp unquoted_source(ast, path) do
    {_, quoted?} =
      Macro.prewalk(ast, false, fn
        {tag, _, _} = node, _acc when tag in [:quote, :unquote, :unquote_splicing] -> {node, true}
        node, acc -> {node, acc}
      end)

    if quoted? do
      {:error, [%{code: :unsupported_quoted_source, path: path}]}
    else
      :ok
    end
  end

  defp location_independent(ast, path) do
    {_, sensitive} =
      Macro.prewalk(ast, false, fn
        {tag, _, _} = node, _acc when tag in [:__DIR__, :__ENV__, :__CALLER__] -> {node, true}
        node, acc -> {node, acc}
      end)

    if sensitive do
      {:error, [%{code: :location_sensitive_source, path: path}]}
    else
      :ok
    end
  end

  defp expressions({:__block__, _, items}), do: items
  defp expressions(nil), do: []
  defp expressions(item), do: [item]

  defp normalize(ast),
    do:
      Macro.prewalk(ast, fn
        {tag, meta, args} when is_list(meta) -> {tag, [], args}
        node -> node
      end)
end
