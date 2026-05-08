defmodule Bylaw.Credo.Check.Elixir.NoPassthroughWrapper do
  @moduledoc """
  Disallows tiny pass-through wrappers that only forward arguments to a single call.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [include_public: false],
    explanations: [
      check: """
      Avoid private functions that only forward their arguments to a single call.
      Inline the call instead.

      This should be refactored:

          defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)

      Into this:

          DateTime.to_iso8601(datetime)

      If the wrapper name materially improves readability, keep it and disable
      this check locally:

          # credo:disable-for-next-line Bylaw.Credo.Check.Elixir.NoPassthroughWrapper
          defp format_datetime(datetime), do: DateTime.to_iso8601(datetime)
      """,
      params: [
        include_public: "When true, also report public `def` passthrough wrappers"
      ]
    ]

  @definitions ~w(def defp)a

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    definition_counts = collect_definition_counts(source_file)

    state = %{
      ctx: ctx,
      include_public?: Params.get(params, :include_public, __MODULE__),
      definition_counts: definition_counts
    }

    Credo.Code.prewalk(source_file, &walk/2, state).ctx.issues
  end

  defp walk({definition, _meta, [head, [do: body]]} = ast, state)
       when definition in @definitions do
    case issue_for_definition(state, definition, head, body) do
      nil -> {ast, state}
      issue -> {ast, %{state | ctx: put_issue(state.ctx, issue)}}
    end
  end

  defp walk(ast, state), do: {ast, state}

  defp issue_for_definition(%{include_public?: false}, :def, _head, _body), do: nil

  defp issue_for_definition(state, definition, head, body) when definition in @definitions do
    case {extract_definition(head), extract_forwarded_call(body)} do
      {{:ok, {name, meta, param_names}}, {:ok, {callee, forwarded_args}}} ->
        arity = Enum.count(param_names)

        if param_names == forwarded_args and
             single_clause_definition?(state, definition, name, arity) do
          format_issue(
            state.ctx,
            message:
              "Avoid tiny indirection in `#{name}/#{arity}`; it only forwards arguments to `#{callee}`. " <>
                "Inline the call unless the wrapper name materially improves readability.",
            trigger: Atom.to_string(name),
            line_no: meta[:line]
          )
        end

      _other ->
        nil
    end
  end

  defp extract_definition({:when, _meta, [_call, _guard]}), do: :error

  defp extract_definition({name, meta, params}) when is_atom(name) and is_list(params) do
    case extract_param_names(params) do
      {:ok, param_names} ->
        if Enum.empty?(param_names) do
          :error
        else
          {:ok, {name, meta, param_names}}
        end

      _other ->
        :error
    end
  end

  defp extract_definition(_head), do: :error

  defp collect_definition_counts(source_file) do
    Credo.Code.prewalk(source_file, &collect_definition/2, %{})
  end

  defp collect_definition({definition, _meta, [head, _body]} = ast, counts)
       when definition in @definitions do
    case definition_signature(head) do
      {:ok, signature} -> {ast, Map.update(counts, {definition, signature}, 1, &(&1 + 1))}
      :error -> {ast, counts}
    end
  end

  defp collect_definition(ast, counts), do: {ast, counts}

  defp definition_signature({:when, _meta, [call, _guard]}), do: definition_signature(call)

  defp definition_signature({name, _meta, params}) when is_atom(name) and is_list(params) do
    {:ok, {name, Enum.count(params)}}
  end

  defp definition_signature(_head), do: :error

  defp single_clause_definition?(state, definition, name, arity) do
    Map.get(state.definition_counts, {definition, {name, arity}}) == 1
  end

  defp extract_param_names(params), do: extract_names(params, &extract_param_name/1)

  defp extract_param_name({:\\, _meta, [param, _default]}), do: extract_param_name(param)
  defp extract_param_name({:=, _meta, [_pattern, param]}), do: extract_param_name(param)

  defp extract_param_name({name, _meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {:ok, name}
  end

  defp extract_param_name(_param), do: :error

  defp extract_forwarded_call({:|>, _meta, [input, call]}) do
    case {extract_arg_name(input), extract_forwarded_pipe_call(call)} do
      {{:ok, input_name}, {:ok, {callee, arg_names}}} ->
        {:ok, {callee, [input_name | arg_names]}}

      _other ->
        :error
    end
  end

  defp extract_forwarded_call({name, _meta, args}) when is_atom(name) and is_list(args) do
    case extract_arg_names(args) do
      {:ok, arg_names} -> {:ok, {"#{name}/#{Enum.count(args)}", arg_names}}
      :error -> :error
    end
  end

  defp extract_forwarded_call(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, modules}, name]}, _meta, args}
       )
       when is_atom(name) and is_list(args) do
    case extract_arg_names(args) do
      {:ok, arg_names} ->
        {:ok, {"#{module_name(modules)}.#{name}/#{Enum.count(args)}", arg_names}}

      :error ->
        :error
    end
  end

  defp extract_forwarded_call(_body), do: :error

  defp extract_forwarded_pipe_call({name, _meta, args}) when is_atom(name) and is_list(args) do
    case extract_arg_names(args) do
      {:ok, arg_names} -> {:ok, {"#{name}/#{Enum.count(args) + 1}", arg_names}}
      :error -> :error
    end
  end

  defp extract_forwarded_pipe_call(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, modules}, name]}, _meta, args}
       )
       when is_atom(name) and is_list(args) do
    case extract_arg_names(args) do
      {:ok, arg_names} ->
        {:ok, {"#{module_name(modules)}.#{name}/#{Enum.count(args) + 1}", arg_names}}

      :error ->
        :error
    end
  end

  defp extract_forwarded_pipe_call(_call), do: :error

  defp extract_arg_names(args), do: extract_names(args, &extract_arg_name/1)

  defp extract_arg_name({name, _meta, context})
       when is_atom(name) and (is_atom(context) or is_nil(context)) do
    {:ok, name}
  end

  defp extract_arg_name(_arg), do: :error

  defp extract_names(items, extractor) do
    case Enum.reduce_while(items, [], &extract_name_step(&1, &2, extractor)) do
      :error -> :error
      names -> {:ok, Enum.reverse(names)}
    end
  end

  defp extract_name_step(item, names, extractor) do
    case extractor.(item) do
      {:ok, name} -> {:cont, [name | names]}
      :error -> {:halt, :error}
    end
  end

  defp module_name(modules), do: Enum.map_join(modules, ".", &Atom.to_string/1)
end
