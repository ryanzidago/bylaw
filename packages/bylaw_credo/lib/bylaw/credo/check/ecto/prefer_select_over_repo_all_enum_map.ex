defmodule Bylaw.Credo.Check.Ecto.PreferSelectOverRepoAllEnumMap do
  @moduledoc """
  Prefers using `select` in an Ecto query over `Repo.all |> Enum.map` when the
  map callback only accesses fields on the record.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Prefer using `select` in the Ecto query over loading full rows with
      `Repo.all` and then mapping them with `Enum.map` to extract fields.

      This should be refactored:

          query
          |> Repo.all()
          |> Enum.map(&%{role: &1.role, content: &1.content})

      Into this:

          query
          |> select([m], %{role: m.role, content: m.content})
          |> Repo.all()

      This pushes the projection down to the database, reducing memory usage
      and data transfer.

      Cases where `Enum.map` references the full record (not just field
      accesses) are allowed, since they cannot be expressed as a `select`:

          # OK - the full record is referenced
          Repo.all(query) |> Enum.map(&%{id: &1.id, record: &1})
      """
    ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  # Pipe form: ... |> Repo.all() |> Enum.map(callback)
  defp walk(
         {:|>, _outer_pipe_meta,
          [
            {:|>, _inner_pipe_meta, [_query, repo_all]},
            {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, :map]}, _call_meta, [callback]}
          ]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, repo_all, callback)}
  end

  # Pipe form: Repo.all(query) |> Enum.map(callback)
  defp walk(
         {:|>, _pipe_meta,
          [
            repo_all,
            {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, :map]}, _call_meta, [callback]}
          ]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, repo_all, callback)}
  end

  # Non-pipe form: Enum.map(Repo.all(query), callback)
  defp walk(
         {{:., meta, [{:__aliases__, _aliases_meta, [:Enum]}, :map]}, _call_meta,
          [repo_all, callback]} = ast,
         ctx
       ) do
    {ast, maybe_put_issue(ctx, meta, repo_all, callback)}
  end

  defp walk(ast, ctx), do: {ast, ctx}

  defp maybe_put_issue(ctx, meta, repo_all, callback) do
    if repo_all_expression?(repo_all) and only_field_accesses?(callback) do
      put_issue(ctx, issue_for(ctx, meta))
    else
      ctx
    end
  end

  # Repo.all(query) or Repo.all(query, opts)
  defp repo_all_expression?({{:., _dot_meta, [repo, :all]}, _call_meta, _args}),
    do: repo_module?(repo)

  # query |> Repo.all() (already unwrapped from outer pipe)
  defp repo_all_expression?({:|>, _pipe_meta, [_query, repo_all_stage]}),
    do: repo_all_stage?(repo_all_stage)

  defp repo_all_expression?(_other), do: false

  defp repo_all_stage?({{:., _dot_meta, [repo, :all]}, _call_meta, _args}), do: repo_module?(repo)
  defp repo_all_stage?(_other), do: false

  defp repo_module?({:__aliases__, _meta, aliases}), do: List.last(aliases) == :Repo
  defp repo_module?(_other), do: false

  # Check whether a callback only accesses fields on its parameter (never uses
  # the parameter "bare"). Returns true when the callback is safe to replace
  # with a `select`, false when the full record is referenced.

  # Capture form: &expr  - parameter is &1
  # But skip function references like &to_dto/1 or &Map.keys/1
  defp only_field_accesses?({:&, _meta, [{:/, _slash_meta, _args}]}), do: false

  defp only_field_accesses?({:&, _meta, [body]}) do
    not bare_capture_var?(body)
  end

  # Anonymous function: fn x -> body end
  defp only_field_accesses?({:fn, _meta, [{:->, _arrow_meta, [[param], body]}]}) do
    case extract_var_name(param) do
      nil -> false
      var_name -> not bare_var_used?(body, var_name)
    end
  end

  defp only_field_accesses?(_other), do: false

  # --- Capture form (&1) helpers ---

  # &1.field - the access itself is fine, don't recurse into &1
  defp bare_capture_var?(
         {{:., _dot_meta, [{:&, _capture_meta, [1]}, _field]}, _call_meta, _args}
       ),
       do: false

  # bare &1
  defp bare_capture_var?({:&, _meta, [1]}), do: true

  # Recurse into any other AST node
  defp bare_capture_var?(list) when is_list(list) do
    Enum.any?(list, &bare_capture_var?/1)
  end

  defp bare_capture_var?({_form, _node_meta, args}) when is_list(args) do
    Enum.any?(args, &bare_capture_var?/1)
  end

  defp bare_capture_var?({left, right}) do
    bare_capture_var?(left) or bare_capture_var?(right)
  end

  defp bare_capture_var?(_other), do: false

  # --- Anonymous function variable helpers ---

  defp extract_var_name({var_name, _meta, context}) when is_atom(var_name) and is_atom(context),
    do: var_name

  defp extract_var_name(_other), do: nil

  # var.field - the access is fine, don't recurse into var
  defp bare_var_used?(
         {{:., _dot_meta, [{var_name, _var_meta, ctx}, _field]}, _call_meta, _args},
         var_name
       )
       when is_atom(ctx),
       do: false

  # bare var
  defp bare_var_used?({var_name, _meta, ctx}, var_name) when is_atom(ctx), do: true

  # Recurse
  defp bare_var_used?(list, var_name) when is_list(list) do
    Enum.any?(list, &bare_var_used?(&1, var_name))
  end

  defp bare_var_used?({_form, _node_meta, args}, var_name) when is_list(args) do
    Enum.any?(args, &bare_var_used?(&1, var_name))
  end

  defp bare_var_used?({left, right}, var_name) do
    bare_var_used?(left, var_name) or bare_var_used?(right, var_name)
  end

  defp bare_var_used?(_other, _var_name), do: false

  defp issue_for(ctx, meta) do
    format_issue(
      ctx,
      message:
        "Prefer using `select` in the Ecto query instead of `Repo.all` followed by `Enum.map` to extract fields.",
      trigger: "Enum.map",
      line_no: meta[:line]
    )
  end
end
