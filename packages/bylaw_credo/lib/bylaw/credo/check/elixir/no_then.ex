defmodule Bylaw.Credo.Check.Elixir.NoThen do
  @moduledoc """
  Prefer explicit control flow over `then/2`.

  ## Examples

  Avoid:

        value
        |> transform()
        |> then(&{:ok, &1})

        then(value, &{:ok, &1})
  Prefer:

        value =
          value
          |> transform()

        {:ok, value}

  ## Notes

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
          {Bylaw.Credo.Check.Elixir.NoThen, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: @moduledoc
    ]

  @doc false
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
