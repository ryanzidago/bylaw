defmodule Bylaw.Credo.Check.Ecto.NamedBinding do
  @moduledoc """
  Prefer named Ecto bindings over positional bindings in composed queries.

  ## Examples

  Avoid:

        User
        |> join(:inner, [u], p in assoc(u, :profile))
        |> where([u, p], p.active)
        |> select([u, p], {u.id, p.display_name})

  Prefer:

        User
        |> from(as: :user)
        |> join(:inner, [user: u], p in assoc(u, :profile), as: :profile)
        |> where([profile: p], p.active)
        |> select([user: u, profile: p], {u.id, p.display_name})

  ## Notes

  Positional bindings make every later query clause depend on the order of
  earlier joins. Adding, removing, or reordering a join can silently change
  what `[u, p]` means in the rest of the pipeline.

  Named bindings make each clause say which relationship it is using, so
  query changes are easier to review and less sensitive to join order.

  Path exclusions are matched against the source filename and are intended for generated files or temporary migration areas.

  The check uses static AST analysis, so dynamic code generation and macro-expanded code may fall outside its signal.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.NamedBinding,
           [
             excluded_paths: ["test/support/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:excluded_paths` - Paths containing any configured string are skipped. Use this for generated files or transitional areas that cannot yet follow named binding conventions.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.NamedBinding, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    category: :warning,
    base_priority: :higher,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: """
        Paths containing any configured string are skipped. Use this for
        generated files or transitional areas that cannot yet follow named
        binding conventions.
        """
      ]
    ]

  @ecto_query_functions ~w(where select select_merge order_by group_by having preload lock distinct update)a
  @ecto_join_functions ~w(join left_join right_join inner_join cross_join full_join)a
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if path_excluded?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp path_excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &String.contains?(filename, &1))
  end

  defp traverse(
         {:|>, _pipe_meta, [{:__aliases__, module_meta, _segments}, {func, _func_meta, _args}]} =
           ast,
         issues,
         issue_meta
       )
       when func in @ecto_query_functions do
    {ast, [issue_for(issue_meta, module_meta[:line] || 0) | issues]}
  end

  defp traverse(
         {:|>, _pipe_meta, [{:__aliases__, module_meta, _segments}, {func, _func_meta, _args}]} =
           ast,
         issues,
         issue_meta
       )
       when func in @ecto_join_functions do
    {ast, [issue_for(issue_meta, module_meta[:line] || 0) | issues]}
  end

  defp traverse(
         {:|>, _pipe_meta,
          [
            {query_var, _var_meta, nil},
            {func, func_meta,
             [[{binding, _binding_meta, _binding_context} | _rest] | _other_args]}
          ]} = ast,
         issues,
         issue_meta
       )
       when func in @ecto_query_functions and is_atom(binding) and is_atom(query_var) do
    {ast, [issue_for(issue_meta, func_meta[:line] || 0) | issues]}
  end

  defp traverse(
         {:|>, _pipe_meta,
          [
            {query_var, _var_meta, nil},
            {func, func_meta,
             [_join_type, [{binding, _binding_meta, _binding_context} | _rest] | _other_args]}
          ]} = ast,
         issues,
         issue_meta
       )
       when func in @ecto_join_functions and is_atom(binding) and is_atom(query_var) do
    {ast, [issue_for(issue_meta, func_meta[:line] || 0) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Use `from(x in Schema, as: :name)` with named bindings `[name: x]` instead of positional bindings.",
      trigger: "|>",
      line_no: line_no
    )
  end
end
