defmodule Bylaw.Credo.Check.Elixir.NoLowLevelProcessPrimitives do
  @moduledoc """
  Disallows direct usage of `Process`, `GenServer`, and `:ets`.

  Stateful and process-based primitives are **exceptions, not
  defaults**. They exist for very specific use cases and should only
  be introduced after gaining explicit approval.

  Most of the time the right answer is simpler than you think - plain
  functions, passing values through arguments, or returning data from
  the caller is almost always preferable to reaching for `Process`,
  `GenServer`, `:ets`, or any other stateful primitive.

  Note: `Agent` is not flagged because it cannot be reliably
  distinguished from aliased application modules (e.g.
  `Bylaw.Agents.Agent`) at the AST level. `Task` is also not
  flagged - it is a reasonable concurrency tool that does not
  introduce hidden state.

  **Before adding process-level machinery, ask yourself:**

  1. Can I solve this with a plain function and its arguments?
  2. Am I introducing state/concurrency where none is needed?
  3. Have I gotten explicit approval to use process primitives here?

  If the answer to all three is "yes, I really need this", disable the
  check for the call site:

      # credo:disable-for-next-line Bylaw.Credo.Check.Elixir.NoLowLevelProcessPrimitives
      Process.put(:key, value)
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: "List of path prefixes or regexes to exclude from this check."
      ]
    ]

  @flagged_modules [:Process, :GenServer]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if excluded?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, fn
      %Regex{} = regex -> Regex.match?(regex, filename)
      path when is_binary(path) -> String.contains?(filename, path)
    end)
  end

  # Process.func(...) / GenServer.func(...)
  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [mod]}, func]}, meta, _args} = ast,
         issues,
         issue_meta
       )
       when mod in @flagged_modules and is_atom(func) do
    {ast, [issue_for(issue_meta, meta[:line] || 0, "#{mod}.#{func}") | issues]}
  end

  # :ets.func(...)
  defp traverse(
         {{:., _dot_meta, [:ets, func]}, meta, _args} = ast,
         issues,
         issue_meta
       )
       when is_atom(func) do
    {ast, [issue_for(issue_meta, meta[:line] || 0, ":ets.#{func}") | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Found `#{trigger}` - stateful/process primitives are exceptions, not defaults. " <>
          "Can you solve this with plain functions and arguments instead? " <>
          "These should only be introduced after gaining explicit approval. " <>
          "If you have approval, disable the check with " <>
          "`# credo:disable-for-next-line`.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
