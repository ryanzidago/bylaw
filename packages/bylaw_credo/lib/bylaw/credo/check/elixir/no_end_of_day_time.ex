defmodule Bylaw.Credo.Check.Elixir.NoEndOfDayTime do
  @moduledoc """
  Avoid `~T[23:59:59]` as an end-of-day bound.

  ### Bad

      occurred_at >= day_start and occurred_at <= ~T[23:59:59]

  ### Why?

  An inclusive `23:59:59` bound misses values with fractional seconds, such
  as `23:59:59.500000`. That creates edge-case bugs for timestamp and time
  comparisons.

  ### Better

      occurred_at >= day_start and occurred_at < next_day_start

  Use the next day's midnight as an exclusive upper bound. Half-open ranges
  include every representable time in the day without guessing precision.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [excluded_paths: ["test/"]],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: """
        Paths containing any configured string are skipped. Defaults to `test/`
        so fixtures and assertions can still describe boundary values directly.
        """
      ]
    ]

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
         {:sigil_T, meta, [{:<<>>, _str_meta, [time_string]}, _modifiers]} = ast,
         issues,
         issue_meta
       )
       when is_binary(time_string) do
    if String.starts_with?(time_string, "23:59:59") do
      {ast, [issue_for(issue_meta, meta[:line] || 0, time_string) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, time_string) do
    format_issue(
      issue_meta,
      message:
        "Avoid using `~T[#{time_string}]` as end of day. Use `~T[00:00:00]` of the next day as an exclusive bound instead.",
      trigger: "~T[#{time_string}]",
      line_no: line_no
    )
  end
end
