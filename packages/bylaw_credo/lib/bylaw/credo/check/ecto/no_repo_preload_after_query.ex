defmodule Bylaw.Credo.Check.Ecto.NoRepoPreloadAfterQuery do
  @moduledoc """
  Do not call `Repo.preload` after loading records with `Repo.one` or
  `Repo.all`. Prefer composing the preload into the Ecto query so the
  preload intent stays visible at the query boundary.

  ## Examples

  Avoid:

        query
        |> Repo.one()
        |> Repo.preload([:message])
  Prefer:

        query
        |> preload([:message])
        |> Repo.one()

  The same rule applies when a local helper hides the `Repo.preload` call:

        query
        |> Repo.one()
        |> preload_message()
  Prefer:

        query
        |> preload([:message])
        |> Repo.one()

  ## Notes

  This check uses static AST analysis, so it favors clear source-level patterns over runtime behavior.

  ## Options

  This check has no check-specific options. Configure it with an empty option list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.NoRepoPreloadAfterQuery, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: @moduledoc
    ]

  alias Credo.SourceFile

  @repo_read_functions [:all, :one, :one!]
  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    ast = SourceFile.ast(source_file)
    ctx = Context.build(source_file, params, __MODULE__)

    state = %{
      ctx: ctx,
      preload_helpers: collect_preload_helpers(ast)
    }

    state =
      ast
      |> Macro.prewalk(state, &walk/2)
      |> elem(1)

    state.ctx.issues
  end

  defp walk({:|>, _pipe_meta, [input, stage]} = ast, state) do
    {ast, maybe_put_pipe_issue(state, input, stage)}
  end

  defp walk({{:., _dot_meta, [repo, :preload]}, meta, [argument | _rest]} = ast, state) do
    state =
      if repo_module?(repo) and query_result_expression?(argument) do
        put_issue_in_state(state, issue_for(state.ctx, meta, "Repo.preload"))
      else
        state
      end

    {ast, state}
  end

  defp walk({name, meta, [argument | rest]} = ast, state)
       when is_atom(name) and is_list(rest) do
    state =
      if preload_helper?(state.preload_helpers, name, Enum.count([argument | rest])) and
           query_result_expression?(argument) do
        put_issue_in_state(state, issue_for(state.ctx, meta, Atom.to_string(name)))
      else
        state
      end

    {ast, state}
  end

  defp walk(ast, state), do: {ast, state}

  defp maybe_put_pipe_issue(state, input, stage) do
    if query_result_expression?(input) do
      case preload_trigger(state.preload_helpers, stage) do
        nil -> state
        {meta, trigger} -> put_issue_in_state(state, issue_for(state.ctx, meta, trigger))
      end
    else
      state
    end
  end

  defp collect_preload_helpers(ast) do
    ast
    |> Macro.prewalk(MapSet.new(), &collect_preload_helper/2)
    |> elem(1)
  end

  defp collect_preload_helper(
         {definition, _meta, [function_head, body]} = node,
         helpers
       )
       when definition in [:def, :defp] do
    case helper_signature(function_head) do
      {name, [first_arg | _rest] = arguments} ->
        {node, maybe_put_preload_helper(helpers, name, arguments, body, first_arg)}

      _other ->
        {node, helpers}
    end
  end

  defp collect_preload_helper(node, helpers), do: {node, helpers}

  defp maybe_put_preload_helper(helpers, name, arguments, body, first_arg) do
    if preloads_first_param?(body, first_arg) do
      MapSet.put(helpers, {name, Enum.count(arguments)})
    else
      helpers
    end
  end

  defp helper_signature({name, _meta, arguments}) when is_atom(name) and is_list(arguments),
    do: {name, arguments}

  defp helper_signature(_other), do: nil

  defp preloads_first_param?(body, first_arg) do
    case extract_do_body(body) do
      nil ->
        false

      do_body ->
        first_arg
        |> pattern_vars()
        |> preloads_any_bound_var?(do_body)
    end
  end

  defp extract_do_body(body) when is_list(body) do
    if Keyword.keyword?(body), do: Keyword.get(body, :do)
  end

  defp extract_do_body(_other), do: nil

  defp pattern_vars(pattern) do
    pattern
    |> Macro.prewalk(MapSet.new(), &collect_pattern_var/2)
    |> elem(1)
  end

  defp collect_pattern_var({name, _meta, context} = node, variables)
       when is_atom(name) and is_atom(context) do
    if bindable_var_name?(name) do
      {node, MapSet.put(variables, name)}
    else
      {node, variables}
    end
  end

  defp collect_pattern_var(node, variables), do: {node, variables}

  defp bindable_var_name?(name) do
    name != :_ and not underscored_var_name?(name)
  end

  defp underscored_var_name?(name) do
    name
    |> Atom.to_string()
    |> String.starts_with?("_")
  end

  defp preloads_any_bound_var?(variables, body) do
    if MapSet.size(variables) == 0 do
      false
    else
      body
      |> Macro.prewalk(false, fn
        node, true ->
          {node, true}

        node, false ->
          {node, preload_uses_bound_var?(node, variables)}
      end)
      |> elem(1)
    end
  end

  defp preload_uses_bound_var?(
         {{:., _dot_meta, [repo, :preload]}, _meta, [argument | _rest]},
         variables
       ) do
    repo_module?(repo) and bound_var_reference?(variables, argument)
  end

  defp preload_uses_bound_var?({:|>, _pipe_meta, [argument, stage]}, variables) do
    bound_var_reference?(variables, argument) and repo_preload_stage?(stage)
  end

  defp preload_uses_bound_var?(_node, _variables), do: false

  defp bound_var_reference?(variables, {name, _meta, context})
       when is_atom(name) and is_atom(context) do
    MapSet.member?(variables, name)
  end

  defp bound_var_reference?(_variables, _other), do: false

  defp preload_trigger(preload_helpers, stage) do
    case repo_preload_trigger(stage) do
      nil -> helper_preload_trigger(preload_helpers, stage)
      trigger -> trigger
    end
  end

  defp repo_preload_trigger({{:., _dot_meta, [repo, :preload]}, meta, _arguments}) do
    if repo_module?(repo), do: {meta, "Repo.preload"}
  end

  defp repo_preload_trigger(_stage), do: nil

  defp helper_preload_trigger(preload_helpers, {name, meta, arguments})
       when is_atom(name) and is_list(arguments) do
    if preload_helper?(preload_helpers, name, Enum.count(arguments) + 1) do
      {meta, Atom.to_string(name)}
    end
  end

  defp helper_preload_trigger(_preload_helpers, _stage), do: nil

  defp preload_helper?(preload_helpers, name, arity) do
    MapSet.member?(preload_helpers, {name, arity})
  end

  defp query_result_expression?({{:., _dot_meta, [repo, function]}, _meta, _arguments})
       when function in @repo_read_functions do
    repo_module?(repo)
  end

  defp query_result_expression?({:|>, _pipe_meta, [_input, stage]}), do: repo_read_stage?(stage)
  defp query_result_expression?(_other), do: false

  defp repo_read_stage?({{:., _dot_meta, [repo, function]}, _meta, _arguments})
       when function in @repo_read_functions do
    repo_module?(repo)
  end

  defp repo_read_stage?(_stage), do: false

  defp repo_preload_stage?({{:., _dot_meta, [repo, :preload]}, _meta, _arguments}),
    do: repo_module?(repo)

  defp repo_preload_stage?(_stage), do: false

  defp repo_module?({:__aliases__, _meta, aliases}), do: List.last(aliases) == :Repo
  defp repo_module?(_other), do: false

  defp put_issue_in_state(state, issue), do: %{state | ctx: put_issue(state.ctx, issue)}

  defp issue_for(ctx, meta, trigger) do
    format_issue(
      ctx,
      message:
        "Do not call `Repo.preload` after `Repo.one` or `Repo.all`. Prefer Ecto's query `preload` API before the Repo read.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
