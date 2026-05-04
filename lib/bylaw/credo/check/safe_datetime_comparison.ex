defmodule Bylaw.Credo.Check.SafeDateTimeComparison do
  @moduledoc """
  Prevents direct comparison operators on likely date/time values.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [datetime_suffixes: ~w(_datetime _at _date _time)]

  @comparison_operators [:==, :!=, :<, :>, :<=, :>=]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    suffixes = Params.get(params, :datetime_suffixes, __MODULE__)
    ecto_where_lines = collect_ecto_where_lines(source_file)

    Credo.Code.prewalk(
      source_file,
      &traverse(&1, &2, issue_meta, suffixes, ecto_where_lines)
    )
  end

  defp collect_ecto_where_lines(source_file) do
    Credo.Code.prewalk(source_file, &collect_where_lines/2, MapSet.new())
  end

  defp collect_where_lines({:|>, _meta, [_left, {:where, _where_meta, _where_args}]} = ast, acc) do
    {ast, MapSet.union(acc, extract_lines_from_ast(ast))}
  end

  defp collect_where_lines({:where, _meta, _args} = ast, acc) do
    {ast, MapSet.union(acc, extract_lines_from_ast(ast))}
  end

  defp collect_where_lines(ast, acc), do: {ast, acc}

  defp extract_lines_from_ast(ast) do
    ast
    |> Macro.prewalk(MapSet.new(), fn
      {_name, meta, _args} = node, acc when is_list(meta) ->
        case Keyword.get(meta, :line) do
          nil -> {node, acc}
          line -> {node, MapSet.put(acc, line)}
        end

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp traverse({op, meta, [left, right]} = ast, issues, issue_meta, suffixes, ecto_where_lines)
       when op in @comparison_operators do
    line_no = meta[:line] || 0

    cond do
      MapSet.member?(ecto_where_lines, line_no) ->
        {ast, issues}

      looks_like_datetime?(left, suffixes) or looks_like_datetime?(right, suffixes) ->
        {ast, [issue_for(issue_meta, line_no, op) | issues]}

      true ->
        {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _suffixes, _ecto_where_lines), do: {ast, issues}

  defp looks_like_datetime?({sigil, _meta, _args}, _suffixes)
       when sigil in [:sigil_U, :sigil_D, :sigil_T, :sigil_N],
       do: true

  defp looks_like_datetime?({name, _meta, context}, suffixes)
       when is_atom(name) and is_atom(context) do
    has_datetime_suffix?(name, suffixes)
  end

  defp looks_like_datetime?({{:., _dot_meta, [_module, field_name]}, _meta, _args}, suffixes)
       when is_atom(field_name) do
    has_datetime_suffix?(field_name, suffixes)
  end

  defp looks_like_datetime?(
         {{:., _dot_meta, [Access, :get]}, _meta, [_target, field_name]},
         suffixes
       )
       when is_atom(field_name) do
    has_datetime_suffix?(field_name, suffixes)
  end

  defp looks_like_datetime?(_node, _suffixes), do: false

  defp has_datetime_suffix?(name, suffixes) do
    name_string = Atom.to_string(name)
    Enum.any?(suffixes, fn suffix -> String.ends_with?(name_string, suffix) end)
  end

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Avoid using #{trigger} for date/time comparison. Use compare/2, before?/2, or after?/2 instead.",
      trigger: to_string(trigger),
      line_no: line_no
    )
  end
end
