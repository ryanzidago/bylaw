defmodule Bylaw.Credo.Check.Elixir.FloatUsage do
  @moduledoc """
  Prefer `Decimal` over floats in Ecto migrations, Ecto schemas, and Elixir code.

  Floats are approximate binary numbers. Many decimal values cannot be represented
  exactly as floats, which can make calculations, rounding, equality checks, and
  persisted values surprising for money, tax, rates, balances, quantities, and
  other business data.

  For example, a float calculation may keep a tiny representation error:

        0.1 + 0.2

  Use the `Decimal` library and Ecto's `:decimal` type when a value needs decimal
  precision or predictable rounding:

        Decimal.add(Decimal.new("0.1"), Decimal.new("0.2"))

  Floats may still be appropriate for approximate measurements, statistics,
  scientific calculations, graphics, telemetry, or other domains where small
  precision differences are expected and acceptable.

  ## Examples

  Avoid:

        add :amount, :float
        field :amount, :float
        Float.round(value, 2)
        amount = 1.25
        @spec amount() :: float()
  Prefer:

        add :amount, :decimal
        field :amount, :decimal
        Decimal.round(value, 2)
        amount = Decimal.new("1.25")
        @spec amount() :: Decimal.t()

  If a float is genuinely required, document the exception and disable the check locally.

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
          {Bylaw.Credo.Check.Elixir.FloatUsage, []}
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

  @migration_functions [:add, :add_if_not_exists, :modify]
  @typespec_attributes [:spec, :type, :typep, :opaque, :callback, :macrocallback]
  @doc false
  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    ctx = Credo.Code.prewalk(source_file, &walk/2, ctx)

    ctx.issues ++ float_literal_issues(source_file, ctx)
  end

  defp walk({op, meta, [_name, :float | _rest]} = ast, ctx) when op in @migration_functions do
    {ast, put_issue(ctx, issue_for(ctx, meta, Atom.to_string(op), migration_message()))}
  end

  defp walk({:field, meta, [_name, :float | _rest]} = ast, ctx) do
    {ast, put_issue(ctx, issue_for(ctx, meta, "field", schema_message()))}
  end

  defp walk(
         {{:., meta, [{:__aliases__, _mod_meta, [:Float]}, function]}, _call_meta, _args} = ast,
         ctx
       ) do
    trigger = "Float.#{function}"
    {ast, put_issue(ctx, issue_for(ctx, meta, trigger, module_message()))}
  end

  defp walk({:@, _attr_meta, [{attribute, _spec_meta, arguments}]} = ast, ctx)
       when attribute in @typespec_attributes do
    {ast, find_typespec_float_issues(arguments, ctx)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp find_typespec_float_issues(arguments, ctx) do
    case Macro.prewalk(arguments, ctx, fn
           {:float, meta, []} = ast, inner_ctx ->
             {ast,
              put_issue(inner_ctx, issue_for(inner_ctx, meta, "float()", typespec_message()))}

           ast, inner_ctx ->
             {ast, inner_ctx}
         end) do
      {_ast, updated_ctx} -> updated_ctx
    end
  end

  defp float_literal_issues(source_file, ctx) do
    ignored_lines =
      ctx.issues
      |> Enum.map(& &1.line_no)
      |> MapSet.new()

    source_file
    |> Credo.Code.to_tokens()
    |> Enum.reduce([], fn
      {:flt, {line_no, _column, _value}, literal}, issues ->
        case MapSet.member?(ignored_lines, line_no) do
          true ->
            issues

          false ->
            [
              issue_for(
                ctx,
                [line: line_no],
                List.to_string(literal),
                float_literal_message()
              )
              | issues
            ]
        end

      _token, issues ->
        issues
    end)
    |> Enum.reverse()
  end

  defp issue_for(ctx, meta, trigger, message) do
    format_issue(
      ctx,
      message: message,
      trigger: trigger,
      line_no: meta[:line]
    )
  end

  defp migration_message, do: "Prefer `:decimal` over `:float` in Ecto migrations."
  defp schema_message, do: "Prefer `:decimal` over `:float` in Ecto schemas."
  defp module_message, do: "Prefer `Decimal` APIs over the `Float` module."
  defp typespec_message, do: "Prefer `Decimal.t()` over `float()` in typespecs."
  defp float_literal_message, do: "Prefer `Decimal.new/1` over float literals."
end
