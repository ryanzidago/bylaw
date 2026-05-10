defmodule Bylaw.Credo.Check.Elixir.FullySpecifiedStructTypes do
  @moduledoc """
  Fully specify struct fields in type declarations instead of using
  empty struct literals such as `%__MODULE__{}`.

  ## Examples

  Avoid:

        @type t :: %__MODULE__{}
        @opaque result :: {:ok, %URI{}}
  Prefer:

        @type t :: %__MODULE__{id: integer(), name: String.t()}
        @opaque result :: {:ok, %URI{host: String.t() | nil, path: String.t()}}

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
          {Bylaw.Credo.Check.Elixir.FullySpecifiedStructTypes, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: @moduledoc
    ]

  @typespec_attributes [:type, :typep, :opaque]
  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:@, _meta, [{attribute, _attribute_meta, arguments}]} = ast, ctx)
       when attribute in @typespec_attributes do
    ctx = Enum.reduce(arguments, ctx, &traverse_attribute/2)
    {ast, ctx}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp traverse_attribute({:"::", _meta, [_name, type]}, ctx), do: traverse_type(type, ctx)
  defp traverse_attribute(ast, ctx), do: traverse_type(ast, ctx)

  defp traverse_type({:%, meta, [module_ast, {:%{}, _fields_meta, []}]} = ast, ctx) do
    ctx = put_issue(ctx, issue_for(ctx, ast, module_ast, meta[:line]))
    traverse_type(module_ast, ctx)
  end

  defp traverse_type(list, ctx) when is_list(list) do
    if Keyword.keyword?(list) do
      Enum.reduce(list, ctx, fn {_key, value}, inner_ctx -> traverse_type(value, inner_ctx) end)
    else
      Enum.reduce(list, ctx, &traverse_type/2)
    end
  end

  defp traverse_type({left, right}, ctx) do
    ctx = traverse_type(left, ctx)
    traverse_type(right, ctx)
  end

  defp traverse_type({_name, _meta, arguments}, ctx) when is_list(arguments) do
    Enum.reduce(arguments, ctx, &traverse_type/2)
  end

  defp traverse_type(_ast, ctx), do: ctx

  defp issue_for(ctx, ast, module_ast, line_no) do
    trigger = Macro.to_string(ast)
    suggestion = "#{Macro.to_string(module_ast)}{field: type}"

    format_issue(
      ctx,
      message: "Fully specify struct fields in types. Prefer `%#{suggestion}` over `#{trigger}`.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
