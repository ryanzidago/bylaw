defmodule Bylaw.Credo.Check.Elixir.PreferEnumCount do
  @moduledoc """
  Prefer `Enum.count/1` over `length/1`.

  ## Examples

  Avoid:

        length(items)
        items |> length()
  Prefer:

        Enum.count(items)
        items |> Enum.count()

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
          {Bylaw.Credo.Check.Elixir.PreferEnumCount, []}
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
