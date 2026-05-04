defmodule Bylaw.Credo.Check.Readability.PipeBasedEctoQueries do
  @moduledoc """
  Enforces pipe-based Ecto query composition instead of passing query clauses
  directly to `from/2`.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Prefer composing Ecto queries with pipes instead of using keyword clauses
      directly inside `from/2`.

      This should be refactored:

          from(u in User, where: u.active, order_by: [asc: u.inserted_at])

      Into this:

          User
          |> where([u], u.active)
          |> order_by([u], asc: u.inserted_at)

      Plain `from/1` usage is still allowed, and `from/2` with only `as:` is
      allowed for named bindings. This check only flags query clauses like
      `where`, `order_by`, joins, `select`, and similar clauses attached
      directly to `from`.
      """
    ]

  @query_clause_keys [
    :combinations,
    :cross_join,
    :distinct,
    :except,
    :except_all,
    :full_join,
    :group_by,
    :having,
    :inner_join,
    :inner_lateral_join,
    :intersect,
    :intersect_all,
    :join,
    :left_join,
    :left_lateral_join,
    :limit,
    :lock,
    :offset,
    :or_having,
    :or_where,
    :order_by,
    :prefix,
    :preload,
    :right_join,
    :select,
    :select_merge,
    :update,
    :where,
    :windows,
    :union,
    :union_all
  ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:from, meta, arguments} = ast, ctx) do
    {ast, maybe_add_issue(ctx, meta, arguments, "from")}
  end

  defp walk(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Ecto, :Query]}, :from]}, meta, arguments} =
           ast,
         ctx
       ) do
    {ast, maybe_add_issue(ctx, meta, arguments, "Ecto.Query.from")}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp maybe_add_issue(ctx, meta, [_queryable, clauses], trigger) when is_list(clauses) do
    case keyword_based_query_clauses?(clauses) do
      true ->
        put_issue(ctx, issue_for(ctx, meta, trigger))

      false ->
        ctx
    end
  end

  defp maybe_add_issue(ctx, _meta, _arguments, _trigger), do: ctx

  defp keyword_based_query_clauses?(clauses) do
    Keyword.keyword?(clauses) and Enum.any?(clauses, &query_clause?/1)
  end

  defp query_clause?({key, _value}), do: key in @query_clause_keys
  defp query_clause?(_other), do: false

  defp issue_for(ctx, meta, trigger) do
    format_issue(
      ctx,
      message: "Use pipe-based Ecto queries instead of keyword clauses in #{trigger}/2.",
      trigger: trigger,
      line_no: meta[:line]
    )
  end
end
