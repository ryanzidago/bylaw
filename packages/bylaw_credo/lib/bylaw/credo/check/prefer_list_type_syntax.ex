defmodule Bylaw.Credo.Check.PreferListTypeSyntax do
  @moduledoc """
  Prefer `list(type)` over `[type]` in typespecs.

  This should be refactored:

      @type names :: [String.t()]
      @spec run([integer()]) :: [atom()]

  Into this:

      @type names :: list(String.t())
      @spec run(list(integer())) :: list(atom())

  Keep `[type, ...]` when the intent is a non-empty list.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: @moduledoc
    ]

  @typespec_attributes [:spec, :type, :typep, :opaque, :callback, :macrocallback]
  @callable_typespec_attributes [:spec, :callback, :macrocallback]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:@, _meta, [{attribute, _attribute_meta, arguments}]} = ast, ctx)
       when attribute in @typespec_attributes do
    ctx = Enum.reduce(arguments, ctx, &traverse_attribute(&1, attribute, &2))
    {ast, ctx}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp traverse_attribute({:when, _meta, [typespec, constraints]}, attribute, ctx) do
    ctx = traverse_attribute(typespec, attribute, ctx)
    traverse_type(constraints, ctx)
  end

  defp traverse_attribute({:"::", _meta, [signature, return_type]}, attribute, ctx)
       when attribute in @callable_typespec_attributes do
    ctx = traverse_signature(signature, ctx)
    traverse_type(return_type, ctx)
  end

  defp traverse_attribute({:"::", _meta, [_name, type]}, _attribute, ctx),
    do: traverse_type(type, ctx)

  defp traverse_attribute(ast, _attribute, ctx), do: traverse_type(ast, ctx)

  defp traverse_signature({_name, _meta, arguments}, ctx) when is_list(arguments) do
    Enum.reduce(arguments, ctx, &traverse_type/2)
  end

  defp traverse_signature(_ast, ctx), do: ctx

  defp traverse_type([], ctx), do: ctx

  defp traverse_type(ast, ctx) when is_list(ast) do
    cond do
      Keyword.keyword?(ast) ->
        Enum.reduce(ast, ctx, fn {_key, value}, inner_ctx -> traverse_type(value, inner_ctx) end)

      nonempty_list_syntax?(ast) ->
        [type | _rest] = ast
        traverse_type(type, ctx)

      function_type_syntax?(ast) ->
        Enum.reduce(ast, ctx, &traverse_function_clause/2)

      single_item_list_type?(ast) ->
        [type] = ast

        ctx = put_issue(ctx, issue_for(ctx, ast, type))
        traverse_type(type, ctx)

      true ->
        Enum.reduce(ast, ctx, &traverse_type/2)
    end
  end

  defp traverse_type({left, right}, ctx) do
    ctx = traverse_type(left, ctx)
    traverse_type(right, ctx)
  end

  defp traverse_type({_name, _meta, arguments}, ctx) when is_list(arguments) do
    Enum.reduce(arguments, ctx, &traverse_type/2)
  end

  defp traverse_type(_ast, ctx), do: ctx

  defp traverse_function_clause({:->, _meta, [arguments, return_type]}, ctx)
       when is_list(arguments) do
    ctx = Enum.reduce(arguments, ctx, &traverse_type/2)
    traverse_type(return_type, ctx)
  end

  defp traverse_function_clause(ast, ctx), do: traverse_type(ast, ctx)

  defp single_item_list_type?([_type]), do: true
  defp single_item_list_type?(_ast), do: false

  defp function_type_syntax?(ast) when is_list(ast) do
    match?([_ | _], ast) and Enum.all?(ast, &match?({:->, _meta, _arguments}, &1))
  end

  defp nonempty_list_syntax?([_type, {:..., _meta, []}]), do: true
  defp nonempty_list_syntax?(_ast), do: false

  defp issue_for(ctx, ast, type) do
    trigger = Macro.to_string(ast)
    suggestion = "list(#{Macro.to_string(type)})"

    format_issue(
      ctx,
      message: "Prefer `#{suggestion}` over `#{trigger}` in typespecs.",
      trigger: trigger,
      line_no: line_no_for(ast)
    )
  end

  defp line_no_for(ast) when is_list(ast), do: Enum.find_value(ast, &line_no_for/1)

  defp line_no_for({left, right}) do
    line_no_for(left) || line_no_for(right)
  end

  defp line_no_for({_name, meta, arguments}) when is_list(meta) and is_list(arguments) do
    meta[:line] || Enum.find_value(arguments, &line_no_for/1)
  end

  defp line_no_for({_name, meta, argument}) when is_list(meta) do
    meta[:line] || line_no_for(argument)
  end

  defp line_no_for(_ast), do: nil
end
