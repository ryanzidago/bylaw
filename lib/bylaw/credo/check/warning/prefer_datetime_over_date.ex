defmodule Bylaw.Credo.Check.Warning.PreferDateTimeOverDate do
  @moduledoc """
  Discourages `:date` in Ecto schemas and migrations in favor of timestamp types.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Prefer `:naive_datetime` or `:utc_datetime` over `:date` in Ecto schemas and
      migrations when you need precise timestamps.

      This check flags:

          schema "events" do
            field :starts_on, :date
          end

          alter table(:events) do
            add :starts_on, :date
            modify :ends_on, :date
          end

      Use `:naive_datetime`, `:utc_datetime`, or `timestamps/1` instead unless the
      field is intentionally a calendar-only value. If a true date-only field is
      required, disable the check locally with Credo.
      """
    ]

  @schema_macros [:schema, :embedded_schema]
  @migration_operations [:add, :add_if_not_exists, :modify]
  @date_type :date

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)

    source_file
    |> Credo.Code.prewalk(&walk_schema/2, ctx)
    |> maybe_check_migration_columns(source_file)
    |> Map.get(:issues, [])
  end

  defp walk_schema({macro, _meta, [[do: block]]} = ast, ctx) when macro in @schema_macros do
    {ast, find_schema_date_fields(block, ctx)}
  end

  defp walk_schema({macro, _meta, [_source, [do: block]]} = ast, ctx)
       when macro in @schema_macros do
    {ast, find_schema_date_fields(block, ctx)}
  end

  defp walk_schema(ast, ctx), do: {ast, ctx}

  defp find_schema_date_fields(block, ctx) do
    block
    |> Macro.prewalk(ctx, fn
      {:field, meta, [_name, @date_type | _rest]} = ast, acc ->
        {ast, put_issue(acc, issue_for(acc, meta, "field", "schema field"))}

      ast, acc ->
        {ast, acc}
    end)
    |> elem(1)
  end

  defp maybe_check_migration_columns(ctx, source_file) do
    if migration_file?(source_file) do
      Credo.Code.prewalk(source_file, &walk_migration/2, ctx)
    else
      ctx
    end
  end

  defp walk_migration({operation, meta, [_name, @date_type | _rest]} = ast, ctx)
       when operation in @migration_operations do
    {ast, put_issue(ctx, issue_for(ctx, meta, Atom.to_string(operation), "migration column"))}
  end

  defp walk_migration(ast, ctx), do: {ast, ctx}

  defp migration_file?(source_file) do
    String.contains?(source_file.filename, "/priv/repo/migrations/") or
      String.starts_with?(source_file.filename, "priv/repo/migrations/")
  end

  defp issue_for(ctx, meta, trigger, subject) do
    format_issue(
      ctx,
      message: "Prefer `:naive_datetime` or `:utc_datetime` over `:date` for #{subject}.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
