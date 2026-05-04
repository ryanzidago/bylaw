defmodule Bylaw.Credo.Check.PreferEnumCount do
  @moduledoc """
  Prefers `Enum.count/1` over `length/1`.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Prefer `Enum.count/1` over `length/1`.

      This should be refactored:

          length(items)
          items |> length()

      Into this:

          Enum.count(items)
          items |> Enum.count()
      """
    ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  # Strip guard expressions so length/1 inside guards is not flagged.
  # length/1 is a BIF allowed in guards; Enum.count/1 is not.
  defp walk({:when, meta, [fun_head, _guard]}, ctx) do
    {{:when, meta, [fun_head, nil]}, ctx}
  end

  defp walk({:length, meta, [_value]} = ast, ctx) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "length"))}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:Kernel]}, :length]}, _call_meta, [_value]} =
           ast,
         ctx
       ) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "Kernel.length"))}
  end

  defp walk({:|>, _meta, [_value, {:length, meta, []}]} = ast, ctx) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "length"))}
  end

  defp walk(
         {:|>, _pipe_meta,
          [
            _value,
            {{:., meta, [{:__aliases__, _aliases_meta, [:Kernel]}, :length]}, _call_meta, []}
          ]} = ast,
         ctx
       ) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "Kernel.length"))}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta, trigger) do
    format_issue(
      ctx,
      message: "Prefer `Enum.count/1` over `#{trigger}/1`.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
