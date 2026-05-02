defmodule Bylaw.Credo.Check.Readability.NoFunctionCallInWithBody do
  @moduledoc """
  Disallows fallible function calls as the return expression in a `with` do-body.

  Uses `Code.Typespec.fetch_specs/1` to inspect the called function's return
  type.  A call is only flagged when its spec includes `:error` or `{:error, _}`
  in the return type.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      The `do` body of a `with` expression should return a value, not call a
      function that could fail.  Move fallible calls into `<-` clauses so that
      every success and every failure flows through the branching.

      This should be refactored:

          with {:ok, record_1} <- create_record() do
            create_record()
          else
            {:error, reason} -> {:error, reason}
          end

      Into this:

          with {:ok, record_1} <- create_record(),
               {:ok, record_2} <- create_record() do
            {:ok, record_2}
          else
            {:error, reason} -> {:error, reason}
          end
      """
    ]

  @ignored_forms ~w[
    __block__ fn case cond if unless for with receive try
    quote unquote unquote_splicing super %{} % |>
  ]a

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    initial_state = %{ctx: ctx, current_module: nil, aliases: %{}, imports: %{}}

    result = Credo.Code.prewalk(source_file, &walk/2, initial_state)
    result.ctx.issues
  end

  defp walk({:defmodule, _meta, [{:__aliases__, _alias_meta, segments} | _rest]} = ast, state) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    {ast, %{state | current_module: Module.concat(segments), aliases: %{}, imports: %{}}}
  end

  defp walk({:alias, _meta, arguments} = ast, state) do
    {ast, %{state | aliases: collect_aliases(arguments, state.aliases)}}
  end

  defp walk({:import, _meta, arguments} = ast, state) do
    {ast, %{state | imports: collect_imports(arguments, state.imports)}}
  end

  defp walk({:with, _meta, arguments} = ast, state) do
    case check_body(arguments, state) do
      nil ->
        {ast, state}

      {line, trigger} ->
        {ast, %{state | ctx: put_issue(state.ctx, issue_for(state.ctx, line, trigger))}}
    end
  end

  defp walk(ast, state), do: {ast, state}

  defp check_body(arguments, state) do
    case List.last(arguments) do
      block when is_list(block) ->
        if Keyword.keyword?(block) and Keyword.has_key?(block, :do) and
             Keyword.has_key?(block, :else) do
          block
          |> Keyword.get(:do)
          |> last_expression()
          |> check_expression(state)
        end

      _non_keyword_block ->
        nil
    end
  end

  defp last_expression({:__block__, _block_meta, exprs}), do: List.last(exprs)
  defp last_expression(expr), do: expr

  # Local function call: func(args)
  defp check_expression({name, meta, args}, state)
       when is_atom(name) and is_list(args) and name not in @ignored_forms do
    arity = Enum.count(args)
    module = resolve_imported_module(state, name, arity) || state.current_module

    if spec_returns_error?(module, name, arity) do
      {meta[:line], "#{name}/#{arity}"}
    end
  end

  # Remote function call: Module.func(args)
  defp check_expression(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, modules}, func_name]}, meta, args},
         state
       )
       when is_list(args) do
    module = resolve_alias(state, modules)
    arity = Enum.count(args)

    if spec_returns_error?(module, func_name, arity) do
      {meta[:line], "#{func_name}/#{arity}"}
    end
  end

  # Pipe chain - resolve the final function call in the pipe
  defp check_expression({:|>, _meta, [_pipe_input, right]}, state) do
    check_pipe_end(right, state)
  end

  defp check_expression(_expr, _state), do: nil

  # The rightmost call in a pipe gets an extra arg (the piped value),
  # so we add 1 to the explicit arity.
  defp check_pipe_end({name, meta, args}, state)
       when is_atom(name) and is_list(args) do
    arity = Enum.count(args) + 1
    module = resolve_imported_module(state, name, arity) || state.current_module

    if spec_returns_error?(module, name, arity) do
      {meta[:line], "|>"}
    end
  end

  defp check_pipe_end(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, modules}, func_name]}, meta, args},
         state
       )
       when is_list(args) do
    module = resolve_alias(state, modules)
    arity = Enum.count(args) + 1

    if spec_returns_error?(module, func_name, arity) do
      {meta[:line], "|>"}
    end
  end

  defp check_pipe_end(_expr, _state), do: nil

  defp collect_aliases([{:__aliases__, _meta, segments}, opts], aliases) when is_list(opts) do
    alias_name =
      case Keyword.get(opts, :as) do
        {:__aliases__, _as_meta, [name]} -> name
        nil -> List.last(segments)
      end

    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Map.put(aliases, alias_name, Module.concat(segments))
  end

  defp collect_aliases([{:__aliases__, _meta, segments}], aliases) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Map.put(aliases, List.last(segments), Module.concat(segments))
  end

  defp collect_aliases(_arguments, aliases), do: aliases

  defp collect_imports([{:__aliases__, _meta, segments}, opts], imports) when is_list(opts) do
    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    module = Module.concat(segments)

    opts
    |> Keyword.get(:only, [])
    |> Enum.reduce(imports, fn {name, arity}, acc ->
      Map.put(acc, {name, arity}, module)
    end)
  end

  defp collect_imports(_args, imports), do: imports

  defp resolve_imported_module(state, name, arity) do
    Map.get(state.imports, {name, arity})
  end

  defp resolve_alias(state, [segment | rest]) do
    case Map.get(state.aliases, segment) do
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      nil -> Module.concat([segment | rest])
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      module -> Module.concat([module | rest])
    end
  end

  # ---------------------------------------------------------------------------
  # Spec introspection
  # ---------------------------------------------------------------------------

  defp spec_returns_error?(module, function, arity) do
    with true <- is_atom(module),
         {:ok, specs} <- Code.Typespec.fetch_specs(module),
         {{^function, ^arity}, spec_asts} <-
           Enum.find(specs, &match?({{^function, ^arity}, _spec_asts}, &1)) do
      Enum.any?(spec_asts, &spec_ast_has_error_return?(&1, module))
    else
      false -> false
      :error -> false
      nil -> false
    end
  end

  defp spec_ast_has_error_return?(spec_ast, module) do
    return_type = extract_return_type(spec_ast)
    type_contains_error?(return_type, module, MapSet.new())
  end

  # A function spec is {:type, line, :fun, [params, return_type]}
  defp extract_return_type({:type, _line, :fun, [_params, return_type]}), do: return_type
  # Bounded fun (with guards): {:type, line, :bounded_fun, [fun_type, constraints]}
  defp extract_return_type({:type, _line, :bounded_fun, [fun_type, _constraints]}),
    do: extract_return_type(fun_type)

  defp extract_return_type(_type_ast), do: nil

  # Walk the type AST looking for bare :error or {:error, _} returns.
  defp type_contains_error?(nil, _module, _seen), do: false

  defp type_contains_error?({:atom, _line, :error}, _module, _seen), do: true

  defp type_contains_error?({:type, _line, :union, types}, module, seen) do
    Enum.any?(types, &type_contains_error?(&1, module, seen))
  end

  defp type_contains_error?(
         {:type, _line, :tuple, [{:atom, _atom_line, :error} | _rest]},
         _module,
         _seen
       ),
       do: true

  defp type_contains_error?({:type, _line, :tuple, _elements}, _module, _seen), do: false

  defp type_contains_error?({:user_type, _line, type_name, type_args}, module, seen) do
    resolve_type(module, type_name, type_args, seen)
  end

  defp type_contains_error?(
         {:remote_type, _line,
          [{:atom, _mod_line, remote_module}, {:atom, _name_line, type_name}, type_args]},
         _module,
         seen
       ) do
    resolve_type(remote_module, type_name, type_args, seen)
  end

  defp type_contains_error?({:type, _line, :any, []}, _module, _seen), do: false
  defp type_contains_error?({:type, _line, :term, []}, _module, _seen), do: false

  defp type_contains_error?(_type_ast, _module, _seen), do: false

  defp resolve_type(module, type_name, type_args, seen) do
    lookup_key = {module, type_name, Enum.count(type_args)}

    if MapSet.member?(seen, lookup_key) do
      false
    else
      seen = MapSet.put(seen, lookup_key)

      with {:ok, types} <- Code.Typespec.fetch_types(module),
           {:ok, type_ast} <- find_type_ast(types, type_name, Enum.count(type_args)) do
        type_contains_error?(type_ast, module, seen)
      else
        :error -> false
      end
    end
  end

  defp find_type_ast(types, type_name, arity) do
    case Enum.find(types, &match_type?(&1, type_name, arity)) do
      {kind, {^type_name, type_ast, args}} when kind in [:type, :opaque] ->
        {:ok, substitute_type_args(type_ast, args)}

      _no_match ->
        :error
    end
  end

  defp match_type?({kind, {name, _type_ast, args}}, type_name, arity)
       when kind in [:type, :opaque] do
    name == type_name and Enum.count(args) == arity
  end

  defp match_type?(_type_entry, _type_name, _arity), do: false

  defp substitute_type_args(type_ast, []), do: type_ast

  defp substitute_type_args(type_ast, args) do
    replacements =
      args
      |> Enum.with_index()
      |> Map.new(fn
        {{:var, _line, name}, index} ->
          # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
          {name, {:var, 0, :"arg#{index}"}}

        {other, _index} ->
          {other, other}
      end)

    Macro.prewalk(type_ast, fn
      {:var, _line, name} = var -> Map.get(replacements, name, var)
      node -> node
    end)
  end

  # ---------------------------------------------------------------------------

  defp issue_for(ctx, line, trigger) do
    format_issue(
      ctx,
      message:
        "Move fallible function calls out of the `with` body into additional `<-` clauses, " <>
          "then return a value like `{:ok, result}` from the body so success and failure paths stay in the branching.",
      trigger: trigger,
      line_no: line
    )
  end
end
