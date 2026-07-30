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

  ## Notes

  This check uses parser metadata to distinguish keyword-form `if` expressions from block-form
  expressions.

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
    case Keyword.has_key?(meta, :do) do
      true -> {ast, ctx}
      false -> {ast, put_issue(ctx, issue_for(ctx, meta))}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp issue_for(ctx, meta) do
    format_issue(
      ctx,
      message: "Use block syntax for `if` expressions instead of `do:` and `else:` keywords.",
      trigger: "if",
      line_no: meta[:line]
    )
  end
end
