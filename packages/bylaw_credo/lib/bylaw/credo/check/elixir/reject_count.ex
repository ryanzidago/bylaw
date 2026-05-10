defmodule Bylaw.Credo.Check.Elixir.RejectCount do
  @moduledoc """
  Use `Enum.count/2` instead of rejecting items and then counting the
  remaining list.

  ## Examples

  Avoid:

        users
        |> Enum.reject(&(&1.status == :inactive))
        |> Enum.count()

  Prefer:

        Enum.count(users, &(&1.status != :inactive))

  ## Notes

  `Enum.reject/2` builds an intermediate list just so `Enum.count/1` can
  count it. The callback is also written in the negative, which makes the
  kept values less obvious.

  `Enum.count/2` performs the count in one pass without allocating the
  rejected list, and the predicate describes the values being counted.

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
          {Bylaw.Credo.Check.Elixir.RejectCount, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    category: :refactor,
    base_priority: :high,
    explanations: [
      check: @moduledoc
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.Code.prewalk(&traverse(&1, &2, issue_meta))
    |> Enum.reverse()
  end

  defp traverse(
         {:|>, _meta,
          [
            {:|>, _pipe_meta,
             [
               _left,
               {{:., _reject_dot_meta, [{:__aliases__, _reject_alias_meta, [:Enum]}, :reject]},
                _reject_meta, _reject_args}
             ]},
            {{:., meta, [{:__aliases__, _count_alias_meta, [:Enum]}, :count]}, _count_meta, []}
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
  end

  defp traverse(
         {{:., meta, [{:__aliases__, _count_alias_meta, [:Enum]}, :count]}, _count_meta,
          [
            {{:., _reject_dot_meta, [{:__aliases__, _reject_alias_meta, [:Enum]}, :reject]},
             _reject_meta, _reject_args}
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
  end

  defp traverse(
         {:|>, _pipe_meta,
          [
            {{:., _reject_dot_meta, [{:__aliases__, _reject_alias_meta, [:Enum]}, :reject]},
             _reject_meta, _reject_args},
            {{:., meta, [{:__aliases__, _count_alias_meta, [:Enum]}, :count]}, _count_meta, []}
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
  end

  defp traverse(
         {{:., meta, [{:__aliases__, _count_alias_meta, [:Enum]}, :count]}, _count_meta,
          [
            {:|>, _pipe_meta,
             [
               _left,
               {{:., _reject_dot_meta, [{:__aliases__, _reject_alias_meta, [:Enum]}, :reject]},
                _reject_meta, _reject_args}
             ]}
          ]} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message: "`Enum.count/2` is more efficient than `Enum.reject/2 |> Enum.count/1`.",
      trigger: "count",
      line_no: line_no
    )
  end
end
