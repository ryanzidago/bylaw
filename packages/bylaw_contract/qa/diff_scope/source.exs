defmodule BylawDiffScope.Source do
  @moduledoc false
  @git_local_env ~w(GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_CONFIG GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_OBJECT_DIRECTORY GIT_DIR GIT_WORK_TREE GIT_IMPLICIT_WORK_TREE GIT_GRAFT_FILE GIT_INDEX_FILE GIT_NO_REPLACE_OBJECTS GIT_REPLACE_REF_BASE GIT_PREFIX GIT_SHALLOW_FILE GIT_COMMON_DIR)

  @doc false
  @spec base(keyword(), String.t() | nil) :: {:ok, String.t() | :all} | {:error, list(map())}
  def base(options, environment) do
    case Keyword.get(options, :diff_base, environment) do
      value when value in [nil, false] -> {:ok, :all}
      value when is_binary(value) and byte_size(value) > 0 -> {:ok, value}
      _ -> {:error, [%{code: :invalid_base}]}
    end
  end

  @doc false
  @spec select(map(), map()) ::
          {:ok, MapSet.t({module(), atom(), arity()})} | {:error, list(map())}
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

  @doc false
  @spec git_select(String.t(), String.t(), list(String.t())) ::
          {:ok, map()} | {:error, list(map())}
  def git_select(directory, reference, paths \\ ["lib"]) do
    with {:ok, ref} when ref != :all <- base([diff_base: reference], nil),
         {:ok, head} <- git(directory, ["rev-parse", "--verify", "HEAD^{commit}"]),
         {:ok, base} <-
           git(directory, ["rev-parse", "--verify", "--end-of-options", ref <> "^{commit}"]),
         {:ok, merge_base} <- git(directory, ["merge-base", base, head]),
         {:ok, status} <-
           git(directory, ["status", "--porcelain", "--untracked-files=all", "--" | paths]),
         :ok <- clean(status),
         {:ok, names} <-
           git(directory, [
             "diff",
             "--name-only",
             "--no-renames",
             "-z",
             merge_base,
             head,
             "--" | paths
           ]),
         names <-
           names
           |> String.split(<<0>>, trim: true)
           |> Enum.filter(&(Path.extname(&1) in [".ex", ".exs"])),
         {:ok, before} <- revision_files(directory, merge_base, names),
         {:ok, current} <- revision_files(directory, head, names),
         {:ok, selected} <- select(before, current) do
      {:ok, %{head: head, base: base, merge_base: merge_base, selected: selected, files: names}}
    else
      {:error, _} = error -> error
      _ -> {:error, [%{code: :invalid_base}]}
    end
  end

  defp clean(""), do: :ok
  defp clean(_), do: {:error, [%{code: :dirty_source}]}

  defp revision_files(directory, revision, names) do
    with {:ok, listing} <- git(directory, ["ls-tree", "-r", "--name-only", "-z", revision]) do
      available = MapSet.new(String.split(listing, <<0>>, trim: true))

      Enum.reduce_while(names, {:ok, %{}}, fn name, {:ok, files} ->
        if MapSet.member?(available, name) do
          case git(directory, ["show", revision <> ":" <> name], false) do
            {:ok, text} -> {:cont, {:ok, Map.put(files, name, text)}}
            error -> {:halt, error}
          end
        else
          {:cont, {:ok, files}}
        end
      end)
    end
  end

  defp git(directory, args, trim \\ true) do
    if !File.dir?(directory), do: raise(ArgumentError, "repository directory is unavailable")

    case System.cmd("git", args,
           cd: directory,
           stderr_to_stdout: true,
           env: Enum.map(@git_local_env, &{&1, nil})
         ) do
      {output, 0} ->
        {:ok, if(trim, do: String.trim_trailing(output, "\n"), else: output)}

      {output, status} ->
        {:error, [%{code: :git_error, command: args, status: status, detail: output}]}
    end
  rescue
    error in [ErlangError, ArgumentError] ->
      {:error, [%{code: :git_unavailable, detail: Exception.message(error)}]}
  end

  defp inventory(files) do
    Enum.reduce_while(Enum.sort(files), {:ok, %{functions: %{}, contexts: %{}}}, fn {path, source},
                                                                                    {:ok, state} ->
      with {:ok, ast} <- Code.string_to_quoted(source, file: path, emit_warnings: false),
           :ok <- location_independent(ast, path),
           {:ok, next} <- modules(expressions(ast), nil, state) do
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
    module =
      if parent && hd(parts) != Elixir,
        do: Module.concat([parent | parts]),
        else: Module.concat(parts)

    with :ok <- no_outer_context(state),
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

  defp module_body(module, forms, state) do
    if Map.has_key?(state.contexts, module) do
      {:error, [%{code: :duplicate_module, module: module}]}
    else
      {nested, local} = Enum.split_with(forms, &match?({:defmodule, _, _}, &1))

      {definitions, contextual_specs, _prefix} =
        Enum.reduce(forms, {[], [], []}, fn form, {definitions, specs, prefix} ->
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

      with :ok <- no_nested_context(nested, context),
           {:ok, state} <- functions(module, definitions, contextual_specs, state),
           {:ok, state} <- modules(nested, module, state),
           do: {:ok, state}
    end
  end

  defp no_outer_context(state) do
    if Enum.any?(Map.get(state.contexts, :top_level, [])),
      do: {:error, [%{code: :unsupported_outer_context}]},
      else: :ok
  end

  defp no_nested_context(nested, context) do
    if Enum.count(nested) > 1 or (Enum.any?(nested) and Enum.any?(context)),
      do: {:error, [%{code: :unsupported_nested_context}]},
      else: :ok
  end

  defp functions(module, definitions, specs, state) do
    Enum.reduce_while(definitions, {:ok, state}, fn {{_, _, [head | _]} = definition, prefix},
                                                    {:ok, state} ->
      case signature(head) do
        {name, args} when is_atom(name) and is_list(args) ->
          key = {module, name, length(args)}

          defaults =
            definitions
            |> Enum.map(fn {{_, _, [other_head | _]}, _} ->
              case signature(other_head) do
                {^name, other_args} when length(other_args) == length(args) ->
                  Enum.count(other_args, &match?({:\\, _, _}, &1))

                _ ->
                  0
              end
            end)
            |> Enum.max(fn -> 0 end)

          own_specs =
            Enum.filter(specs, fn spec ->
              case spec_signature(elem(spec, 0)) do
                {^name, arity} -> arity in (length(args) - defaults)..length(args)
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

  defp signature({:when, _, [head | _]}), do: signature(head)
  defp signature({name, _, nil}) when is_atom(name), do: {name, []}
  defp signature({name, _, args}) when is_atom(name) and is_list(args), do: {name, args}
  defp signature(_), do: :unsupported
  defp spec_signature({:@, _, [{:spec, _, [spec]}]}), do: spec_head(spec)
  defp spec_head({:when, _, [spec | _]}), do: spec_head(spec)

  defp spec_head({:"::", _, [head, _]}) do
    case signature(head) do
      {name, args} -> {name, length(args)}
      _ -> :unsupported
    end
  end

  defp spec_head(_), do: :unsupported

  defp location_independent(ast, path) do
    {_, sensitive} =
      Macro.prewalk(ast, false, fn
        {tag, _, _} = node, _acc when tag in [:__DIR__, :__ENV__, :__CALLER__] -> {node, true}
        node, acc -> {node, acc}
      end)

    if sensitive, do: {:error, [%{code: :location_sensitive_source, path: path}]}, else: :ok
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
