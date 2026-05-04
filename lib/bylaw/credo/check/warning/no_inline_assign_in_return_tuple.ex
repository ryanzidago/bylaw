defmodule Bylaw.Credo.Check.Warning.NoInlineAssignInReturnTuple do
  @moduledoc """
  Prevents inline `assign/2,3` and `assign_new/3` calls inside LiveView return tuples.
  """

  use Credo.Check, base_priority: :higher, category: :warning

  @assign_functions [:assign, :assign_new]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    if liveview_file?(source_file.filename) do
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.SourceFile.ast()
      |> find_violations(issue_meta)
    else
      []
    end
  end

  defp liveview_file?(filename) do
    String.contains?(filename, ["_live/", "live/", "_component", "component"]) or
      String.ends_with?(filename, ["_live.ex", "_component.ex"])
  end

  defp find_violations({:ok, ast}, issue_meta) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
  end

  defp find_violations(ast, issue_meta) when is_tuple(ast) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
  end

  defp find_violations(_error, _issue_meta), do: []

  defp traverse(
         {return_atom, {assign_fn, assign_meta, _args}} = node,
         issues,
         issue_meta
       )
       when return_atom in [:ok, :noreply] and assign_fn in @assign_functions do
    {node, [create_issue(issue_meta, assign_meta, return_atom, assign_fn) | issues]}
  end

  defp traverse(
         {return_atom, {:|>, _pipe_meta, _pipe_args} = pipe_expr} = node,
         issues,
         issue_meta
       )
       when return_atom in [:ok, :noreply] do
    case find_assign_in_pipe(pipe_expr) do
      {assign_fn, assign_meta} ->
        {node, [create_issue(issue_meta, assign_meta, return_atom, assign_fn) | issues]}

      nil ->
        {node, issues}
    end
  end

  defp traverse(
         {:{}, _tuple_meta, [:reply, _value, {assign_fn, assign_meta, _args}]} = node,
         issues,
         issue_meta
       )
       when assign_fn in @assign_functions do
    {node, [create_issue(issue_meta, assign_meta, :reply, assign_fn) | issues]}
  end

  defp traverse(
         {:{}, _tuple_meta, [:reply, _value, {:|>, _pipe_meta, _pipe_args} = pipe_expr]} = node,
         issues,
         issue_meta
       ) do
    case find_assign_in_pipe(pipe_expr) do
      {assign_fn, assign_meta} ->
        {node, [create_issue(issue_meta, assign_meta, :reply, assign_fn) | issues]}

      nil ->
        {node, issues}
    end
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}

  defp find_assign_in_pipe(
         {:|>, _pipe_meta, [{:|>, _nested_meta, _nested_args} = nested_pipe, _right]}
       ) do
    find_assign_in_pipe(nested_pipe)
  end

  defp find_assign_in_pipe({:|>, _pipe_meta, [_left, {assign_fn, assign_meta, _assign_args}]})
       when assign_fn in @assign_functions do
    {assign_fn, assign_meta}
  end

  defp find_assign_in_pipe(_node), do: nil

  defp create_issue(issue_meta, meta, return_atom, assign_fn) do
    format_issue(
      issue_meta,
      message:
        "Extract `#{assign_fn}/2,3` call before the return tuple. Use `{:#{return_atom}, socket}` instead of `{:#{return_atom}, #{assign_fn}(socket, ...)}`.",
      trigger: "#{assign_fn}",
      line_no: meta[:line] || 0
    )
  end
end
