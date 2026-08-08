defmodule Bylaw.Credo.Check.Elixir.PreferBlockIf do
  @moduledoc """
  Prefer block syntax for `if` expressions.

  ## Examples

  Avoid:

      if valid?,
        do: :ok,
        else: {:error, :invalid}

  Prefer:

      if valid? do
        :ok
      else
        {:error, :invalid}
      end


  This check uses parser metadata to distinguish keyword-form `if` expressions from block-form
  expressions.

  Block syntax keeps both branches visually grouped with the condition, which
  makes multi-line control flow easier to scan and extend without reformatting
  a keyword list.
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
          {Bylaw.Credo.Check.Elixir.PreferBlockIf, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    tags: [:readability],
    explanations: [
      check: @moduledoc
    ]

  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:if, meta, _arguments} = ast, ctx) do
    check_syntax(ast, meta, ctx)
  end

  defp walk(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, kernel}, :if]}, meta, _arguments} = ast,
         ctx
       )
       when kernel in [[:Kernel], [Elixir, :Kernel]] do
    check_syntax(ast, meta, ctx)
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp check_syntax(ast, meta, ctx) do
    case Keyword.has_key?(meta, :do) do
      true -> {ast, ctx}
      false -> {ast, put_issue(ctx, issue_for(ctx, meta))}
    end
  end

  defp issue_for(ctx, meta) do
    format_issue(
      ctx,
      message: "Use block syntax for `if` expressions instead of `do:` and `else:` keywords.",
      trigger: "if",
      line_no: meta[:line]
    )
  end
end
