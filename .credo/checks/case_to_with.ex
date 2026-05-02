defmodule Bylaw.Credo.Check.Refactor.CaseToWith do
  @moduledoc """
  Flags `case` expressions matching on `{:ok, _}` / `{:error, _}` with
  pass-through error clauses that should be refactored into `with` expressions.
  """

  use Credo.Check,
    base_priority: :high,
    category: :refactor,
    explanations: [
      check: """
      Prefer `with` over `case` when the only purpose of the error branch is to
      pass errors through unchanged.

      Move every fallible call - including the one in the ok branch - into a
      `<-` clause so that all success and failure paths flow through the `with`
      branching.

      This should be refactored:

          case fetch_user(id) do
            {:ok, user} -> update_user(user)
            {:error, error} -> {:error, error}
          end

      Into this:

          with {:ok, user} <- fetch_user(id),
               {:ok, result} <- update_user(user) do
            {:ok, result}
          else
            {:error, error} -> {:error, error}
          end

      Once you have a `with`, the companion checks enforce its style:

        - `Readability.WithElseClause` - requires an explicit `else` clause.
        - `Readability.NoCatchAllInWithElse` - requires specific patterns
          like `{:error, reason}` instead of catch-all variables.
        - `Readability.NoFunctionCallInWithBody` - ensures the `do` body
          returns a value, not another fallible call.
      """
    ]

  @non_call_forms ~w[
    __block__ fn cond if unless for with receive try
    quote unquote unquote_splicing super %{} % = :: <<>> when ..
  ]a

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:case, meta, [subject, block]} = ast, ctx) when is_list(block) do
    clauses =
      block
      |> Keyword.get(:do, [])
      |> List.wrap()

    if flaggable?(subject, clauses) do
      {ast, put_issue(ctx, issue_for(ctx, meta))}
    else
      {ast, ctx}
    end
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp flaggable?(subject, clauses) do
    function_call?(subject) and has_ok_error_shape?(clauses)
  end

  # -------------------------------------------------------------------
  # Subject detection - must be a function call, not a variable/literal
  # -------------------------------------------------------------------

  defp function_call?({name, _meta, args})
       when is_atom(name) and is_list(args) and name not in @non_call_forms,
       do: true

  defp function_call?({{:., _dot_meta, _callee}, _meta, args}) when is_list(args), do: true
  defp function_call?(_expr), do: false

  # -------------------------------------------------------------------
  # Clause classification
  # -------------------------------------------------------------------

  defp has_ok_error_shape?(clauses) do
    # credo:disable-for-next-line Bylaw.Credo.Check.Design.NoRaise
    {ok_clauses, error_clauses, other_clauses} = classify_clauses(clauses)

    Enum.any?(ok_clauses) and
      Enum.any?(error_clauses) and
      Enum.empty?(other_clauses) and
      Enum.all?(error_clauses, &error_passthrough?/1) and
      Enum.all?(ok_clauses, &ok_branch_has_operation?/1)
  end

  defp classify_clauses(clauses) do
    Enum.reduce(clauses, {[], [], []}, fn clause, {ok, err, other} ->
      case classify_clause(clause) do
        :ok -> {[clause | ok], err, other}
        :error -> {ok, [clause | err], other}
        :other -> {ok, err, [clause | other]}
      end
    end)
  end

  defp classify_clause({:->, _meta, [[pattern], _body]}) do
    cond do
      ok_pattern?(pattern) -> :ok
      error_pattern?(pattern) -> :error
      true -> :other
    end
  end

  defp classify_clause(_clause), do: :other

  defp ok_pattern?({:ok, _value}), do: true
  defp ok_pattern?({:=, _meta, [{:ok, _value}, _var]}), do: true
  defp ok_pattern?({:=, _meta, [_var, {:ok, _value}]}), do: true
  defp ok_pattern?(_pattern), do: false

  defp error_pattern?(:error), do: true
  defp error_pattern?({:error, _value}), do: true
  defp error_pattern?({:=, _meta, [{:error, _value}, _var]}), do: true
  defp error_pattern?({:=, _meta, [_var, {:error, _value}]}), do: true
  defp error_pattern?(_pattern), do: false

  # -------------------------------------------------------------------
  # Error pass-through detection
  # -------------------------------------------------------------------

  defp error_passthrough?({:->, _meta, [[pattern], body]}) do
    cond do
      # :error -> :error
      pattern == :error and body == :error ->
        true

      # {:error, var} -> {:error, var}
      match?({:error, _val}, pattern) and match?({:error, _val}, body) ->
        ast_equal?(pattern, body)

      # {:error, _} = var -> var  /  var = {:error, _} -> var
      match?({:=, _meta, _sides}, pattern) ->
        assign_passthrough?(pattern, body)

      true ->
        false
    end
  end

  defp error_passthrough?(_clause), do: false

  defp assign_passthrough?({:=, _meta, [left, right]}, body) do
    cond do
      error_pattern?(left) and variable?(right) -> ast_equal?(right, body)
      error_pattern?(right) and variable?(left) -> ast_equal?(left, body)
      true -> false
    end
  end

  defp variable?({name, _meta, context}) when is_atom(name) and is_atom(context), do: true
  defp variable?(_expr), do: false

  # -------------------------------------------------------------------
  # Ok branch - must end with a function call / operation
  # -------------------------------------------------------------------

  defp ok_branch_has_operation?({:->, _meta, [[_pattern], body]}) do
    body
    |> last_expression()
    |> operation?()
  end

  defp ok_branch_has_operation?(_clause), do: false

  defp last_expression({:__block__, _meta, exprs}), do: List.last(exprs)
  defp last_expression(expr), do: expr

  defp operation?({name, _meta, args})
       when is_atom(name) and is_list(args) and name not in @non_call_forms,
       do: true

  defp operation?({{:., _dot_meta, [{:__aliases__, _alias_meta, _segments}, _func]}, _meta, args})
       when is_list(args),
       do: true

  defp operation?(_expr), do: false

  # -------------------------------------------------------------------
  # AST comparison ignoring metadata
  # -------------------------------------------------------------------

  defp ast_equal?({a1, _meta1, c1}, {a2, _meta2, c2}) do
    ast_equal?(a1, a2) and ast_equal?(c1, c2)
  end

  defp ast_equal?({a1, b1}, {a2, b2}) do
    ast_equal?(a1, a2) and ast_equal?(b1, b2)
  end

  defp ast_equal?(list_a, list_b) when is_list(list_a) and is_list(list_b) do
    Enum.count(list_a) == Enum.count(list_b) and
      list_a
      |> Enum.zip(list_b)
      |> Enum.all?(fn {x, y} -> ast_equal?(x, y) end)
  end

  defp ast_equal?(same, same), do: true
  defp ast_equal?(_left, _right), do: false

  # -------------------------------------------------------------------

  defp issue_for(ctx, meta) do
    format_issue(
      ctx,
      message:
        "Refactor this `case` into `with ... <- ... do ... else {:error, reason} -> {:error, reason} end` " <>
          "when the error branch only passes tagged errors through unchanged.",
      trigger: "case",
      line_no: meta[:line]
    )
  end
end
