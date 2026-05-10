defmodule Bylaw.Credo.Check.Elixir.NoRaise do
  @moduledoc """
  Prefer returning tagged results and handling them with `with` expressions
  that include an explicit `else` clause at application boundaries.

  ## Examples

  Avoid:

        user = Repo.get!(User, id)
        {:ok, account} = Accounts.fetch_account(user)
        raise "boom"
  Prefer:

        with {:ok, user} <- Accounts.fetch_user(id),
             {:ok, account} <- Accounts.fetch_account(user) do
          {:ok, account}
        else
          {:error, reason} -> {:error, reason}
        end

  ## Notes

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
          {Bylaw.Credo.Check.Elixir.NoRaise,
           [
             excluded_paths: ["test/support/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:excluded_paths` - List of paths or regex to exclude from this check

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoRaise, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: "List of paths or regex to exclude from this check"
      ]
    ]

  alias Credo.SourceFile

  @definition_ops [:def, :defp, :defmacro, :defmacrop]
  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)

    case ignore_path?(source_file.filename, ctx.params.excluded_paths) do
      true ->
        []

      false ->
        source_file
        |> SourceFile.ast()
        |> Macro.traverse(initial_state(ctx), &prewalk/2, &postwalk/2)
        |> elem(1)
        |> Map.get(:ctx)
        |> Map.get(:issues)
    end
  end

  defp initial_state(ctx) do
    %{
      ctx: ctx,
      pending_definition_heads: [],
      active_definition_heads: []
    }
  end

  defp prewalk(ast, state) do
    state =
      state
      |> maybe_enter_definition_head(ast)
      |> maybe_register_definition_head(ast)
      |> maybe_add_issue(ast)

    {ast, state}
  end

  defp postwalk(ast, state) do
    {ast, maybe_leave_definition_head(state, ast)}
  end

  defp maybe_register_definition_head(
         state,
         {op, _meta, [head, _body]}
       )
       when op in @definition_ops do
    pending_heads = state.pending_definition_heads
    %{state | pending_definition_heads: [head | pending_heads]}
  end

  defp maybe_register_definition_head(state, _ast), do: state

  defp maybe_enter_definition_head(
         %{pending_definition_heads: [ast | _rest]} = state,
         ast
       ) do
    pending_heads = tl(state.pending_definition_heads)
    active_heads = state.active_definition_heads

    %{
      state
      | pending_definition_heads: pending_heads,
        active_definition_heads: [ast | active_heads]
    }
  end

  defp maybe_enter_definition_head(state, _ast), do: state

  defp maybe_leave_definition_head(
         %{active_definition_heads: [ast | active_heads]} = state,
         ast
       ) do
    %{state | active_definition_heads: active_heads}
  end

  defp maybe_leave_definition_head(state, _ast), do: state

  defp maybe_add_issue(%{active_definition_heads: [_head | _rest]} = state, _ast), do: state

  defp maybe_add_issue(state, ast) do
    ctx = state.ctx

    case issue_for_ast(ctx, ast) do
      nil ->
        state

      issue ->
        %{state | ctx: put_issue(ctx, issue)}
    end
  end

  defp issue_for_ast(
         ctx,
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:Kernel]}, name]}, meta, arguments} =
           ast
       )
       when name in [:raise, :reraise] and is_list(arguments) do
    issue_for(ctx, meta, trigger_for_call(ast), raise_message())
  end

  defp issue_for_ast(ctx, {name, meta, arguments} = ast)
       when name in [:raise, :reraise] and is_list(arguments) do
    issue_for(ctx, meta, trigger_for_call(ast), raise_message())
  end

  defp issue_for_ast(ctx, {{:., _dot_meta, [_receiver, name]}, meta, arguments} = ast)
       when is_atom(name) and is_list(arguments) do
    if bang_call?(name) do
      issue_for(ctx, meta, trigger_for_call(ast), bang_message())
    end
  end

  defp issue_for_ast(ctx, {:=, meta, [pattern, value]}) do
    if not variable_pattern?(pattern) and not raise_like_expression?(value) and
         call_like_expression?(value) do
      issue_for(ctx, meta, "=", match_message())
    end
  end

  defp issue_for_ast(ctx, {name, meta, arguments} = ast)
       when is_atom(name) and is_list(arguments) do
    if bang_call?(name) and not Macro.operator?(name, Enum.count(arguments)) do
      issue_for(ctx, meta, trigger_for_call(ast), bang_message())
    end
  end

  defp issue_for_ast(_ctx, _ast), do: nil

  defp issue_for(ctx, meta, trigger, message) do
    format_issue(
      ctx,
      message: message,
      trigger: trigger,
      line_no: meta[:line]
    )
  end

  defp trigger_for_call(ast) do
    ast
    |> Macro.to_string()
    |> String.replace(~r/\(.*\)$/s, "")
  end

  defp raise_message do
    "Avoid explicit raises in application code. Return tagged results and propagate them with `with ... <- ... do ... else {:error, reason} -> {:error, reason} end`."
  end

  defp bang_message do
    "Avoid bang functions in application code. Call non-bang variants and propagate tagged results with `with ... <- ... do ... else {:error, reason} -> {:error, reason} end`."
  end

  defp match_message do
    "Avoid assertive matches on function results. Replace them with tagged-result flow in `with ... <- ... do ... else {:error, reason} -> {:error, reason} end`."
  end

  defp bang_call?(name) do
    name
    |> Atom.to_string()
    |> String.ends_with?("!")
  end

  defp call_like_expression?({:|>, _meta, _args}), do: true

  defp call_like_expression?({{:., _dot_meta, [_receiver, name]}, _meta, arguments})
       when is_atom(name) and is_list(arguments) do
    true
  end

  defp call_like_expression?({name, _meta, arguments})
       when is_atom(name) and is_list(arguments) do
    not Macro.special_form?(name, Enum.count(arguments)) and
      not Macro.operator?(name, Enum.count(arguments))
  end

  defp call_like_expression?(_ast), do: false

  defp raise_like_expression?(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:Kernel]}, name]}, _meta, arguments}
       )
       when name in [:raise, :reraise] and is_list(arguments) do
    true
  end

  defp raise_like_expression?({name, _meta, arguments})
       when name in [:raise, :reraise] and is_list(arguments) do
    true
  end

  defp raise_like_expression?({{:., _dot_meta, [_receiver, name]}, _meta, arguments})
       when is_atom(name) and is_list(arguments) do
    bang_call?(name) or Enum.any?(arguments, &raise_like_expression?/1)
  end

  defp raise_like_expression?({name, _meta, arguments})
       when is_atom(name) and is_list(arguments) do
    (bang_call?(name) and not Macro.operator?(name, Enum.count(arguments))) or
      Enum.any?(arguments, &raise_like_expression?/1)
  end

  defp raise_like_expression?(list) when is_list(list) do
    Enum.any?(list, &raise_like_expression?/1)
  end

  defp raise_like_expression?(_ast), do: false

  defp variable_pattern?({name, _meta, context}) when is_atom(name) and is_atom(context),
    do: true

  defp variable_pattern?(_pattern), do: false

  defp ignore_path?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &matches?(filename, &1))
  end

  defp matches?(filename, %Regex{} = regex), do: Regex.match?(regex, filename)
  defp matches?(filename, path) when is_binary(path), do: String.starts_with?(filename, path)
end
