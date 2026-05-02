defmodule Bylaw.Credo.Check.Warning.NoRepoMutationInLoop do
  @moduledoc """
  Disallows mutating `Repo` calls inside loops unless the loop is already
  wrapped in a transaction.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [excluded_paths: ["test/", "_test.exs"]],
    explanations: [
      check: """
      Avoid mutating the database inside `Enum` loops or `for` comprehensions
      unless the loop itself runs inside a transaction.

      This should be refactored:

          Enum.each(items, fn item ->
            Repo.update!(Changeset.change(item, status: :done))
          end)

      Into this:

          Repo.transact(fn ->
            Enum.each(items, fn item ->
              Repo.update!(Changeset.change(item, status: :done))
            end)
          end)

      This prevents partial writes when a later iteration fails.
      """,
      params: [
        excluded_paths: "List of path prefixes or regexes to exclude from this check."
      ]
    ]

  alias Credo.SourceFile

  @repo_write_functions [
    :insert,
    :insert!,
    :insert_or_update,
    :insert_or_update!,
    :update,
    :update!,
    :delete,
    :delete!,
    :insert_all,
    :update_all,
    :delete_all
  ]

  @transaction_functions [:transact, :transaction]

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)

    if excluded?(source_file.filename, ctx.params.excluded_paths) do
      []
    else
      case source_file
           |> SourceFile.ast()
           |> Macro.traverse(initial_state(ctx), &prewalk/2, &postwalk/2) do
        {_ast, traversal_state} ->
          traversal_state.ctx.issues
      end
    end
  end

  defp initial_state(ctx) do
    %{
      ctx: ctx,
      immediate_callbacks: MapSet.new(),
      suspended_loop_stacks: [],
      transaction_depth: 0,
      loop_stack: []
    }
  end

  defp prewalk(ast, state) do
    state =
      state
      |> register_immediate_callbacks(ast)
      |> maybe_enter_transaction(ast)
      |> maybe_enter_loop(ast)
      |> maybe_suspend_loop_context(ast)
      |> maybe_add_issue(ast)

    {ast, state}
  end

  defp postwalk(ast, state) do
    state =
      state
      |> maybe_restore_loop_context(ast)
      |> maybe_leave_loop(ast)
      |> maybe_leave_transaction(ast)

    {ast, state}
  end

  defp register_immediate_callbacks(state, ast) do
    immediate_callbacks = immediate_callbacks(ast)

    if Enum.empty?(immediate_callbacks) do
      state
    else
      %{
        state
        | immediate_callbacks:
            Enum.reduce(immediate_callbacks, state.immediate_callbacks, &MapSet.put(&2, &1))
      }
    end
  end

  defp maybe_enter_transaction(state, ast) do
    if transaction_call?(ast) do
      %{state | transaction_depth: state.transaction_depth + 1}
    else
      state
    end
  end

  defp maybe_leave_transaction(state, ast) do
    if transaction_call?(ast) do
      %{state | transaction_depth: state.transaction_depth - 1}
    else
      state
    end
  end

  defp maybe_enter_loop(state, ast) do
    if loop_expression?(ast) do
      %{state | loop_stack: [state.transaction_depth > 0 | state.loop_stack]}
    else
      state
    end
  end

  defp maybe_leave_loop(%{loop_stack: [_loop | rest]} = state, ast) do
    if loop_expression?(ast) do
      %{state | loop_stack: rest}
    else
      state
    end
  end

  defp maybe_leave_loop(state, _ast), do: state

  defp maybe_suspend_loop_context(state, ast) do
    if anonymous_function?(ast) and not immediate_callback?(state, ast) and
         not Enum.empty?(state.loop_stack) do
      %{
        state
        | suspended_loop_stacks: [state.loop_stack | state.suspended_loop_stacks],
          loop_stack: []
      }
    else
      state
    end
  end

  defp maybe_restore_loop_context(state, ast) do
    if anonymous_function?(ast) and not immediate_callback?(state, ast) and
         not Enum.empty?(state.suspended_loop_stacks) do
      case state.suspended_loop_stacks do
        [restored_loop_stack | rest] ->
          %{state | suspended_loop_stacks: rest, loop_stack: restored_loop_stack}

        [] ->
          state
      end
    else
      state
    end
  end

  defp maybe_add_issue(state, ast) do
    case issue_for_ast(state, ast) do
      nil -> state
      issue -> %{state | ctx: put_issue(state.ctx, issue)}
    end
  end

  defp issue_for_ast(state, ast) do
    loop_stack = state.loop_stack
    ctx = state.ctx

    if Enum.any?(loop_stack, &(!&1)) do
      case repo_write_trigger(ast) do
        {meta, trigger} ->
          issue_for(ctx, meta, trigger)

        nil ->
          nil
      end
    end
  end

  defp issue_for(ctx, meta, trigger) do
    format_issue(
      ctx,
      message:
        "Avoid mutating `Repo` calls inside loops unless the loop is wrapped in " <>
          "`Repo.transact` (or `Repo.transaction`).",
      trigger: trigger,
      line_no: meta[:line]
    )
  end

  defp repo_write_trigger({{:., _dot_meta, [repo, function]}, meta, _args})
       when function in @repo_write_functions do
    if repo_module?(repo) do
      {meta, "Repo.#{function}"}
    end
  end

  defp repo_write_trigger(_ast), do: nil

  defp transaction_call?({{:., _dot_meta, [repo, function]}, _meta, _args})
       when function in @transaction_functions do
    repo_module?(repo)
  end

  defp transaction_call?(_ast), do: false

  defp loop_expression?({:for, _meta, _args}), do: true

  defp loop_expression?({{:., _dot_meta, [enum_module, _function]}, _meta, arguments}) do
    enum_module?(enum_module) and Enum.any?(arguments, &callback?/1)
  end

  defp loop_expression?(_ast), do: false

  defp immediate_callbacks({{:., _dot_meta, [module, function]}, _meta, arguments})
       when function in @transaction_functions do
    if repo_module?(module) do
      Enum.filter(arguments, &callback?/1)
    else
      []
    end
  end

  defp immediate_callbacks({{:., _dot_meta, [enum_module, _function]}, _meta, arguments}) do
    if enum_module?(enum_module) do
      Enum.filter(arguments, &callback?/1)
    else
      []
    end
  end

  defp immediate_callbacks(_ast), do: []

  defp anonymous_function?({:fn, _meta, _args}), do: true
  defp anonymous_function?({:&, _meta, _args}), do: true
  defp anonymous_function?(_ast), do: false

  defp immediate_callback?(state, ast), do: MapSet.member?(state.immediate_callbacks, ast)

  defp callback?({:fn, _meta, _args}), do: true
  defp callback?({:&, _meta, _args}), do: true
  defp callback?(_ast), do: false

  defp repo_module?({:__aliases__, _meta, aliases}), do: List.last(aliases) == :Repo
  defp repo_module?(_ast), do: false

  defp enum_module?({:__aliases__, _meta, aliases}), do: List.last(aliases) == :Enum
  defp enum_module?(_ast), do: false

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, fn
      %Regex{} = regex -> Regex.match?(regex, filename)
      path when is_binary(path) -> String.contains?(filename, path)
    end)
  end
end
