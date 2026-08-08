defmodule Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes do
  @moduledoc """
  Avoid calls into application and dependency modules from module attributes.

  ## Examples

  Avoid:

      @some_values MyApp.SomeModule.some_function()

  Prefer:

      def some_values do
        MyApp.SomeModule.some_function()
      end

  Literal values are accepted:

      @some_values [:one, :two]

  Calls into Elixir and OTP standard-library modules are accepted by default
  because they do not add dependencies between project files:

      @some_values Enum.uniq([:one, :one])

  When compile-time evaluation is intentional, keep the call and disable this
  check locally:

      # credo:disable-for-next-line Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes
      @some_values MyApp.SomeModule.some_function()


  Typespec attributes are ignored because calls such as `String.t()` describe
  types and do not execute the named function.

  External function captures stored in attributes are reported because the
  compiler tracks them as compile-time dependencies too.

  It recognizes statically named Elixir and Erlang modules, including nested
  calls inside an attribute value.

  Module attributes are evaluated at compile time. Calling another module from
  an attribute creates a compile-time dependency and embeds the returned value
  in the compiled consumer.
  ## Options

  - `:allow_standard_library` - When true, accept calls into modules shipped by
    the Elixir, Kernel, and standard-library OTP applications. Defaults to true.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes, []}
        ]
      }
    ]
  }
  ```

  To report standard-library calls as well:

  ```elixir
  {Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes,
   [allow_standard_library: false]}
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    tags: [:architecture],
    param_defaults: [allow_standard_library: true],
    explanations: [
      check: @moduledoc,
      params: [
        allow_standard_library:
          "When true, accept calls into Elixir and OTP standard-library modules"
      ]
    ]

  @standard_library_applications [:elixir, :kernel, :stdlib]
  @definition_ops [:def, :defp, :defmacro, :defmacrop]
  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)

    state = %{
      alias_scopes: [%{}],
      ctx: ctx,
      allowed_module_keys: allowed_module_keys(params)
    }

    source_file
    |> Credo.SourceFile.ast()
    |> Macro.traverse(state, &prewalk/2, &postwalk/2)
    |> elem(1)
    |> Map.fetch!(:ctx)
    |> Map.fetch!(:issues)
  end

  defp prewalk({:quote, _meta, _arguments}, state), do: {nil, state}

  defp prewalk({definition, _meta, _arguments}, state) when definition in @definition_ops,
    do: {nil, state}

  defp prewalk({:defmodule, _meta, _arguments} = ast, state) do
    {ast, push_alias_scope(state)}
  end

  defp prewalk({:alias, _meta, _arguments} = ast, state) do
    aliases = update_aliases(current_aliases(state), ast)
    {ast, put_current_aliases(state, aliases)}
  end

  defp prewalk({:@, _meta, [{attribute, _attribute_meta, [value]}]} = ast, state)
       when attribute not in @typespec_attributes do
    ctx =
      value
      |> disallowed_calls(state.allowed_module_keys, current_aliases(state))
      |> Enum.reduce(state.ctx, &put_call_issue(&1, attribute, &2))

    {ast, %{state | ctx: ctx}}
  end

  defp prewalk(ast, state), do: {ast, state}

  defp postwalk({:defmodule, _meta, _arguments} = ast, state) do
    {ast, pop_alias_scope(state)}
  end

  defp postwalk(ast, state), do: {ast, state}

  defp disallowed_calls(value, allowed_module_keys, aliases) do
    {_value, calls} =
      Macro.prewalk(value, [], &collect_call(&1, &2, allowed_module_keys, aliases))

    Enum.reverse(calls)
  end

  defp collect_call({:quote, _meta, _arguments}, calls, _allowed_module_keys, _aliases),
    do: {nil, calls}

  defp collect_call(
         {:&, _capture_meta, [{:/, _arity_meta, [call_ast, arity]}]},
         calls,
         allowed_module_keys,
         aliases
       )
       when is_integer(arity) do
    case remote_call(call_ast, aliases, arity) do
      {:ok, call} -> collect_remote_call(nil, call, calls, allowed_module_keys)
      :error -> {call_ast, calls}
    end
  end

  defp collect_call(ast, calls, allowed_module_keys, aliases) do
    case remote_call(ast, aliases) do
      {:ok, call} -> collect_remote_call(ast, call, calls, allowed_module_keys)
      :error -> {ast, calls}
    end
  end

  defp collect_remote_call(ast, call, calls, allowed_module_keys) do
    if MapSet.member?(allowed_module_keys, call.module_key) do
      {ast, calls}
    else
      {ast, [call | calls]}
    end
  end

  defp remote_call(ast, aliases, arity_override \\ nil)

  defp remote_call(
         {{:., dot_meta, [module_ast, function]}, _meta, arguments},
         aliases,
         arity_override
       )
       when is_atom(function) and is_list(arguments) do
    case static_module(module_ast, aliases) do
      {:ok, {module_key, module_name}} ->
        call = %{
          arity: arity_override || Enum.count(arguments),
          function: function,
          meta: [
            line: dot_meta[:line],
            column: dot_meta[:column] - String.length(module_name)
          ],
          module_key: module_key,
          module_name: module_name
        }

        {:ok, call}

      :error ->
        :error
    end
  end

  defp remote_call(_ast, _aliases, _arity_override), do: :error

  defp static_module({:__MODULE__, _meta, nil}, _aliases) do
    {:ok, {{:elixir, "__MODULE__"}, "__MODULE__"}}
  end

  defp static_module({:__aliases__, _meta, modules}, aliases) when is_list(modules) do
    expanded_modules = expand_alias(modules, aliases, MapSet.new())

    with {:ok, module_name} <- module_parts_name(modules),
         {:ok, module_key_name} <- module_key_name(expanded_modules) do
      {:ok, {{:elixir, module_key_name}, module_name}}
    else
      :error -> :error
    end
  end

  defp static_module(module, _aliases) when is_atom(module) do
    {module_key, module_name} = module_identity(module)
    {:ok, {module_key, module_name}}
  end

  defp static_module(_module_ast, _aliases), do: :error

  defp module_key_name([:"Elixir" | nested_modules]), do: module_parts_name(nested_modules)
  defp module_key_name(modules), do: module_parts_name(modules)

  defp module_parts_name([]), do: :error

  defp module_parts_name(modules) do
    names =
      Enum.reduce_while(modules, [], fn module, names ->
        case module_part_name(module) do
          {:ok, name} -> {:cont, [name | names]}
          :error -> {:halt, :error}
        end
      end)

    case names do
      :error ->
        :error

      names ->
        module_name =
          names
          |> Enum.reverse()
          |> Enum.join(".")

        {:ok, module_name}
    end
  end

  defp module_part_name({:__MODULE__, _meta, nil}), do: {:ok, "__MODULE__"}
  defp module_part_name(module) when is_atom(module), do: {:ok, Atom.to_string(module)}
  defp module_part_name(_module), do: :error

  defp expand_alias([:"Elixir" | _modules] = modules, _aliases, _seen), do: modules

  defp expand_alias([alias_name | suffix] = modules, aliases, seen)
       when is_atom(alias_name) do
    case Map.fetch(aliases, alias_name) do
      {:ok, prefix} ->
        if MapSet.member?(seen, alias_name) do
          modules
        else
          expand_alias(prefix ++ suffix, aliases, MapSet.put(seen, alias_name))
        end

      :error ->
        modules
    end
  end

  defp expand_alias(modules, _aliases, _seen), do: modules

  defp put_call_issue(call, attribute, ctx) do
    trigger = "#{call.module_name}.#{call.function}"

    issue =
      format_issue(ctx,
        message:
          "`#{trigger}/#{call.arity}` in `@#{attribute}` creates a compile-time dependency and " <>
            "embeds its result. Call it from a function unless compile-time evaluation is intentional.",
        trigger: trigger,
        line_no: call.meta[:line],
        column: call.meta[:column]
      )

    put_issue(ctx, issue)
  end

  defp allowed_module_keys(params) do
    if Params.get(params, :allow_standard_library, __MODULE__) do
      standard_library_module_keys()
    else
      MapSet.new()
    end
  end

  defp standard_library_module_keys do
    @standard_library_applications
    |> Enum.flat_map(&Application.spec(&1, :modules))
    |> Enum.map(fn module -> elem(module_identity(module), 0) end)
    |> MapSet.new()
    |> MapSet.put({:erlang, "erlang"})
  end

  defp push_alias_scope(%{alias_scopes: [aliases | _rest] = alias_scopes} = state) do
    %{state | alias_scopes: [aliases | alias_scopes]}
  end

  defp pop_alias_scope(%{alias_scopes: [_aliases, outer_aliases | rest]} = state) do
    %{state | alias_scopes: [outer_aliases | rest]}
  end

  defp current_aliases(%{alias_scopes: [aliases | _rest]}), do: aliases

  defp put_current_aliases(%{alias_scopes: [_aliases | rest]} = state, aliases) do
    %{state | alias_scopes: [aliases | rest]}
  end

  defp update_aliases(
         aliases,
         {:alias, _meta, [{:__aliases__, _alias_meta, parts}, options]}
       )
       when is_list(options) do
    alias_name =
      case Keyword.get(options, :as) do
        {:__aliases__, _as_meta, [name]} -> name
        _other -> List.last(parts)
      end

    Map.put(aliases, alias_name, parts)
  end

  defp update_aliases(aliases, {:alias, _meta, [{:__aliases__, _alias_meta, parts}]}) do
    Map.put(aliases, List.last(parts), parts)
  end

  defp update_aliases(
         aliases,
         {:alias, _meta,
          [
            {{:., _dot_meta, [{:__aliases__, _alias_meta, prefix}, :{}]}, _call_meta,
             grouped_aliases}
          ]}
       ) do
    Enum.reduce(grouped_aliases, aliases, fn
      {:__aliases__, _grouped_meta, suffix}, aliases ->
        parts = prefix ++ suffix
        Map.put(aliases, List.last(parts), parts)

      _other, aliases ->
        aliases
    end)
  end

  defp update_aliases(aliases, _alias_ast), do: aliases

  defp module_identity(module) do
    case Atom.to_string(module) do
      "Elixir." <> module_name -> {{:elixir, module_name}, module_name}
      module_name -> {{:erlang, module_name}, ":#{module_name}"}
    end
  end
end
