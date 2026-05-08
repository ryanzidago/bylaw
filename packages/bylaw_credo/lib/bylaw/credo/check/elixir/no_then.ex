defmodule Bylaw.Credo.Check.Elixir.NoThen do
  @moduledoc """
  Disallows `then/2` to keep control flow explicit.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Prefer explicit control flow over `then/2`.

      This should be refactored:

          value
          |> transform()
          |> then(&{:ok, &1})

          then(value, &{:ok, &1})

      Into this:

          value =
            value
            |> transform()

          {:ok, value}
      """
    ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:then, meta, [_value, _fun]} = ast, ctx) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "then"))}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:Kernel]}, :then]}, _call_meta,
          [_value, _fun]} = ast,
         ctx
       ) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "Kernel.then"))}
  end

  defp walk({:|>, _pipe_meta, [_value, {:then, meta, [_fun]}]} = ast, ctx) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "then"))}
  end

  defp walk(
         {:|>, _pipe_meta,
          [
            _value,
            {{:., meta, [{:__aliases__, _aliases_meta, [:Kernel]}, :then]}, _call_meta, [_fun]}
          ]} =
           ast,
         ctx
       ) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "Kernel.then"))}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta, trigger) do
    format_issue(
      ctx,
      message: "Avoid `#{trigger}/2`; prefer explicit control flow instead of `then`.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
