defmodule Bylaw.Credo.Check.EctoNamedBinding do
  @moduledoc """
  Prefers named Ecto bindings over positional bindings.
  """

  use Credo.Check,
    category: :warning,
    base_priority: :higher,
    param_defaults: [excluded_paths: []]

  @ecto_query_functions ~w(where select select_merge order_by group_by having preload lock distinct update)a
  @ecto_join_functions ~w(join left_join right_join inner_join cross_join full_join)a

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if path_excluded?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp path_excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &String.contains?(filename, &1))
  end

  defp traverse(
         {:|>, _pipe_meta, [{:__aliases__, module_meta, _segments}, {func, _func_meta, _args}]} =
           ast,
         issues,
         issue_meta
       )
       when func in @ecto_query_functions do
    {ast, [issue_for(issue_meta, module_meta[:line] || 0) | issues]}
  end

  defp traverse(
         {:|>, _pipe_meta, [{:__aliases__, module_meta, _segments}, {func, _func_meta, _args}]} =
           ast,
         issues,
         issue_meta
       )
       when func in @ecto_join_functions do
    {ast, [issue_for(issue_meta, module_meta[:line] || 0) | issues]}
  end

  defp traverse(
         {:|>, _pipe_meta,
          [
            {query_var, _var_meta, nil},
            {func, func_meta,
             [[{binding, _binding_meta, _binding_context} | _rest] | _other_args]}
          ]} = ast,
         issues,
         issue_meta
       )
       when func in @ecto_query_functions and is_atom(binding) and is_atom(query_var) do
    {ast, [issue_for(issue_meta, func_meta[:line] || 0) | issues]}
  end

  defp traverse(
         {:|>, _pipe_meta,
          [
            {query_var, _var_meta, nil},
            {func, func_meta,
             [_join_type, [{binding, _binding_meta, _binding_context} | _rest] | _other_args]}
          ]} = ast,
         issues,
         issue_meta
       )
       when func in @ecto_join_functions and is_atom(binding) and is_atom(query_var) do
    {ast, [issue_for(issue_meta, func_meta[:line] || 0) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Use `from(x in Schema, as: :name)` with named bindings `[name: x]` instead of positional bindings.",
      trigger: "|>",
      line_no: line_no
    )
  end
end
