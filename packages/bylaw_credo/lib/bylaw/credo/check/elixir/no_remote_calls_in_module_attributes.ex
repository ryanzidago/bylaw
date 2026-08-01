defmodule Bylaw.Credo.Check.Elixir.NoRemoteCallsInModuleAttributes do
  @moduledoc """
  Avoid calls into application and dependency modules from module attributes.

  Module attributes are evaluated at compile time. Calling another module from
  an attribute creates a compile-time dependency and embeds the returned value
  in the compiled consumer.

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

  ## Notes

  Typespec attributes are ignored because calls such as `String.t()` describe
  types and do not execute the named function.

  External function captures stored in attributes are reported because the
  compiler tracks them as compile-time dependencies too.

  This check uses static AST analysis. It recognizes statically named Elixir
  and Erlang modules, including nested calls inside an attribute value.

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
    param_defaults: [allow_standard_library: true],
    explanations: [
      check: @moduledoc,
      params: [
        allow_standard_library:
          "When true, accept calls into Elixir and OTP standard-library modules"
      ]
    ]

  @standard_library_applications [:elixir, :kernel, :stdlib]
  @typespec_attributes [:callback, :macrocallback, :opaque, :spec, :type, :typep]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)

    state = %{
      ctx: ctx,
      allowed_module_keys: allowed_module_keys(params)
    }

    Credo.Code.prewalk(source_file, &walk/2, state).ctx.issues
  end

  defp walk({:@, _meta, [{attribute, _attribute_meta, [value]}]} = ast, state)
       when attribute not in @typespec_attributes do
    ctx =
      value
      |> disallowed_calls(state.allowed_module_keys)
      |> Enum.reduce(state.ctx, &put_call_issue(&1, attribute, &2))

    {ast, %{state | ctx: ctx}}
  end

  defp walk(ast, state), do: {ast, state}

  defp disallowed_calls(value, allowed_module_keys) do
    {_value, calls} =
      Macro.prewalk(value, [], &collect_call(&1, &2, allowed_module_keys))

    Enum.reverse(calls)
  end

  defp collect_call(ast, calls, allowed_module_keys) do
    case remote_call(ast) do
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

  defp remote_call({{:., dot_meta, [module_ast, function]}, _meta, arguments})
       when is_atom(function) and is_list(arguments) do
    case static_module(module_ast) do
      {:ok, {module_key, module_name}} ->
        call = %{
          arity: Enum.count(arguments),
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

  defp remote_call(_ast), do: :error

  defp static_module({:__aliases__, _meta, modules}) when is_list(modules) do
    module_name = Enum.map_join(modules, ".", &Atom.to_string/1)

    module_key_name =
      case modules do
        [:"Elixir" | nested_modules] -> Enum.map_join(nested_modules, ".", &Atom.to_string/1)
        _modules -> module_name
      end

    {:ok, {{:elixir, module_key_name}, module_name}}
  end

  defp static_module(module) when is_atom(module) do
    {module_key, module_name} = module_identity(module)
    {:ok, {module_key, module_name}}
  end

  defp static_module(_module_ast), do: :error

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

  defp module_identity(module) do
    case Atom.to_string(module) do
      "Elixir." <> module_name -> {{:elixir, module_name}, module_name}
      module_name -> {{:erlang, module_name}, ":#{module_name}"}
    end
  end
end
