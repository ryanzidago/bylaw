defmodule Bylaw.Credo.Check.Elixir.PreferEnumUniqBy do
  @moduledoc """
  Prefer `Enum.uniq_by/2` before projecting fields with `Enum.map/2`.

  This should be refactored:

      items
      |> Enum.map(& &1.step)
      |> Enum.uniq()

  Into this:

      items
      |> Enum.uniq_by(& &1.step)
      |> Enum.map(& &1.step)

  This keeps the uniqueness rule attached to the original items instead of
  first projecting values and then deduplicating the projected list.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: @moduledoc
    ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk(
         {:|>, _pipe_meta, [map_expression, {{:., meta, [enum_module, :uniq]}, _call_meta, []}]} =
           ast,
         ctx
       ) do
    if enum_module?(enum_module) do
      case projection_callback(map_expression) do
        {:ok, callback} -> {ast, put_issue(ctx, issue_for(ctx, meta, callback))}
        :error -> {ast, ctx}
      end
    else
      {ast, ctx}
    end
  end

  defp walk(
         {{:., meta, [enum_module, :uniq]}, _call_meta, [map_expression]} = ast,
         ctx
       ) do
    if enum_module?(enum_module) do
      case projection_callback(map_expression) do
        {:ok, callback} -> {ast, put_issue(ctx, issue_for(ctx, meta, callback))}
        :error -> {ast, ctx}
      end
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp projection_callback({:|>, _pipe_meta, [_enumerable, map_stage]}),
    do: projection_callback_from_map_stage(map_stage)

  defp projection_callback(
         {{:., _dot_meta, [enum_module, :map]}, _call_meta, [_enumerable, callback]}
       )
       when is_tuple(enum_module),
       do: projection_callback_from_callback(callback)

  defp projection_callback(_other), do: :error

  defp projection_callback_from_map_stage(
         {{:., _dot_meta, [enum_module, :map]}, _call_meta, [callback]}
       ) do
    if enum_module?(enum_module) do
      projection_callback_from_callback(callback)
    else
      :error
    end
  end

  defp projection_callback_from_map_stage(_other), do: :error

  defp projection_callback_from_callback(callback) do
    if field_projection?(callback) do
      {:ok, callback}
    else
      :error
    end
  end

  defp field_projection?({:&, _meta, [body]}), do: capture_field_chain?(body)

  defp field_projection?({:fn, _meta, [{:->, _arrow_meta, [[param], body]}]}) do
    case extract_var_name(param) do
      nil -> false
      var_name -> variable_field_chain?(body, var_name)
    end
  end

  defp field_projection?(_other), do: false

  defp capture_field_chain?({{:., _dot_meta, [base, _field]}, _call_meta, []}),
    do: capture_root?(base)

  defp capture_field_chain?(_other), do: false

  defp capture_root?({:&, _meta, [1]}), do: true
  defp capture_root?(field_access), do: capture_field_chain?(field_access)

  defp variable_field_chain?({{:., _dot_meta, [base, _field]}, _call_meta, []}, var_name),
    do: variable_root?(base, var_name)

  defp variable_field_chain?(_other, _var_name), do: false

  defp variable_root?({var_name, _meta, context}, var_name) when is_atom(context), do: true
  defp variable_root?(field_access, var_name), do: variable_field_chain?(field_access, var_name)

  defp extract_var_name({var_name, _meta, context})
       when is_atom(var_name) and is_atom(context),
       do: var_name

  defp extract_var_name(_other), do: nil

  defp enum_module?({:__aliases__, _meta, [:Enum]}), do: true
  defp enum_module?(_other), do: false

  defp issue_for(ctx, meta, callback) do
    callback_string = Macro.to_string(callback)

    format_issue(
      ctx,
      message:
        "Prefer `Enum.uniq_by/2` before projecting fields. Rewrite as `Enum.uniq_by(#{callback_string}) |> Enum.map(#{callback_string})`.",
      trigger: "Enum.uniq",
      line_no: meta[:line]
    )
  end
end
