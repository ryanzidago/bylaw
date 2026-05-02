defmodule Bylaw.Credo.Check.Readability.UseMaybeInFunctionName do
  @moduledoc """
  Prefers `maybe_` for conditionally executed function names.
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [
      check: """
      Use `maybe_` in function names that only perform work conditionally.

      This should be refactored:

          def complete_run_if_needed(run), do: ...

      Into this:

          def maybe_complete_run(run), do: ...

      A leading `maybe_` keeps the conditional intent visible without coupling
      the naming convention to a specific suffix like `_if_needed`.
      """
    ]

  @named_definitions [:def, :defp, :defmacro, :defmacrop, :defdelegate]
  @conditional_name_patterns [
    ~r/^(?<stem>.+)_if_needed(?<suffix>[!?])?$/
  ]

  @impl Credo.Check
  def run(source_file, params \\ []) do
    initial_state = %{
      ctx: Context.build(source_file, params, __MODULE__),
      seen_signatures: MapSet.new()
    }

    result = Credo.Code.prewalk(source_file, &walk/2, initial_state)
    result.ctx.issues
  end

  defp walk({definition, _meta, arguments} = ast, state)
       when definition in @named_definitions and is_list(arguments) do
    case extract_signature(List.first(arguments)) do
      nil ->
        {ast, state}

      {name, line_no, arity} ->
        maybe_add_issue(ast, state, name, line_no, arity)
    end
  end

  defp walk(ast, state), do: {ast, state}

  defp maybe_add_issue(ast, state, name, line_no, arity) do
    signature = {name, arity}

    cond do
      MapSet.member?(state.seen_signatures, signature) ->
        {ast, state}

      suggestion = maybe_name_suggestion(name) ->
        issue =
          format_issue(
            state.ctx,
            message:
              "Use `maybe_` in conditional function names. Rename `#{name}` to `#{suggestion}`.",
            trigger: name,
            line_no: line_no
          )

        state = %{
          state
          | ctx: put_issue(state.ctx, issue),
            seen_signatures: MapSet.put(state.seen_signatures, signature)
        }

        {ast, state}

      true ->
        {ast, %{state | seen_signatures: MapSet.put(state.seen_signatures, signature)}}
    end
  end

  defp extract_signature({:when, _meta, [call, _guard]}), do: extract_signature(call)

  defp extract_signature({name, meta, args})
       when is_atom(name) and (is_list(args) or is_nil(args)) do
    arity =
      args
      |> List.wrap()
      |> Enum.count()

    {Atom.to_string(name), meta[:line], arity}
  end

  defp extract_signature(_ast), do: nil

  defp maybe_name_suggestion(name) do
    Enum.find_value(@conditional_name_patterns, fn pattern ->
      case Regex.named_captures(pattern, name) do
        captures when is_map(captures) ->
          build_maybe_name(captures)

        nil ->
          nil
      end
    end)
  end

  defp build_maybe_name(captures) do
    stem = Map.get(captures, "stem")
    suffix = Map.get(captures, "suffix", "")

    "maybe_#{stem}#{suffix}"
  end
end
