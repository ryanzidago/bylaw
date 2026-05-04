defmodule Bylaw.Credo.Check.FilterRejectFirst do
  @moduledoc """
  Prefers `Enum.find/2` over `Enum.filter/2 |> List.first()` or `Enum.reject/2 |> List.first()`.
  """

  use Credo.Check, category: :refactor, base_priority: :high

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
    |> Enum.reverse()
  end

  # Enum.filter/reject |> List.first()
  defp traverse(
         {:|>, _pipe_meta,
          [
            {:|>, _inner_pipe_meta,
             [
               _source,
               {{:., _enum_dot_meta, [{:__aliases__, _enum_meta, [:Enum]}, func]},
                _enum_call_meta, _enum_args}
             ]},
            {{:., meta, [{:__aliases__, _list_meta, [:List]}, :first]}, _list_call_meta, args}
          ]} = ast,
         issues,
         issue_meta
       )
       when func in [:filter, :reject] and length(args) <= 1 do
    {ast, [issue_for(issue_meta, meta[:line] || 0, func) | issues]}
  end

  # Enum.filter/reject(...) |> List.first()
  defp traverse(
         {:|>, _pipe_meta,
          [
            {{:., _enum_dot_meta, [{:__aliases__, _enum_meta, [:Enum]}, func]}, _enum_call_meta,
             _enum_args},
            {{:., meta, [{:__aliases__, _list_meta, [:List]}, :first]}, _list_call_meta, args}
          ]} = ast,
         issues,
         issue_meta
       )
       when func in [:filter, :reject] and length(args) <= 1 do
    {ast, [issue_for(issue_meta, meta[:line] || 0, func) | issues]}
  end

  # List.first(Enum.filter/reject(...))
  defp traverse(
         {{:., meta, [{:__aliases__, _list_meta, [:List]}, :first]}, _list_call_meta,
          [
            {{:., _enum_dot_meta, [{:__aliases__, _enum_meta, [:Enum]}, func]}, _enum_call_meta,
             _enum_args}
            | _rest
          ]} = ast,
         issues,
         issue_meta
       )
       when func in [:filter, :reject] do
    {ast, [issue_for(issue_meta, meta[:line] || 0, func) | issues]}
  end

  # List.first(x |> Enum.filter/reject(...))
  defp traverse(
         {{:., meta, [{:__aliases__, _list_meta, [:List]}, :first]}, _list_call_meta,
          [
            {:|>, _pipe_meta,
             [
               _source,
               {{:., _enum_dot_meta, [{:__aliases__, _enum_meta, [:Enum]}, func]},
                _enum_call_meta, _enum_args}
             ]}
            | _rest
          ]} = ast,
         issues,
         issue_meta
       )
       when func in [:filter, :reject] do
    {ast, [issue_for(issue_meta, meta[:line] || 0, func) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, func) do
    format_issue(
      issue_meta,
      message: "`Enum.find/2` is more efficient than `Enum.#{func}/2 |> List.first/1`.",
      trigger: "first",
      line_no: line_no
    )
  end
end
