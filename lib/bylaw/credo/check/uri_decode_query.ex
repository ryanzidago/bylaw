defmodule Bylaw.Credo.Check.URIDecodeQuery do
  @moduledoc """
  Discourages `URI.decode_query/1` in favor of `Plug.Conn.Query.decode/1`.
  """

  use Credo.Check, category: :warning, base_priority: :higher

  @replacement_module Plug.Conn.Query
  @replacement_function :decode

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  defp traverse(
         {:., _dot_meta, [{:__aliases__, meta, [:URI]}, :decode_query]} = ast,
         issues,
         issue_meta
       ) do
    {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Use #{@replacement_module}.#{@replacement_function}/1 instead of URI.decode_query/1. " <>
          "URI.decode_query/1 handles array parameters incorrectly.",
      trigger: "URI.decode_query",
      line_no: line_no
    )
  end
end
