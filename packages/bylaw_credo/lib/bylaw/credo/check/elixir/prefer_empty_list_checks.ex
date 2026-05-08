defmodule Bylaw.Credo.Check.Elixir.PreferEmptyListChecks do
  @moduledoc """
  Prefer `Enum.empty?/1` and `Enum.any?/1` over comparing collections to `[]`.

  This should be refactored:

      items == []
      items != []

  Into this:

      Enum.empty?(items)
      Enum.any?(items)
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: @moduledoc
    ]

  @empty_list_operators [:==, :===]
  @non_empty_list_operators [:!=, :!==]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({op, meta, [_value, []]} = ast, ctx) when op in @empty_list_operators do
    {ast, put_issue(ctx, issue_for(ctx, meta, Atom.to_string(op), "Enum.empty?/1"))}
  end

  defp walk({op, meta, [[], _value]} = ast, ctx) when op in @empty_list_operators do
    {ast, put_issue(ctx, issue_for(ctx, meta, Atom.to_string(op), "Enum.empty?/1"))}
  end

  defp walk({op, meta, [_value, []]} = ast, ctx) when op in @non_empty_list_operators do
    {ast, put_issue(ctx, issue_for(ctx, meta, Atom.to_string(op), "Enum.any?/1"))}
  end

  defp walk({op, meta, [[], _value]} = ast, ctx) when op in @non_empty_list_operators do
    {ast, put_issue(ctx, issue_for(ctx, meta, Atom.to_string(op), "Enum.any?/1"))}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta, trigger, suggestion) do
    format_issue(
      ctx,
      message: "Prefer `#{suggestion}` over comparing to `[]`.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
