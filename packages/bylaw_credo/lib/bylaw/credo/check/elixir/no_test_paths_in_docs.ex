defmodule Bylaw.Credo.Check.Elixir.NoTestPathsInDocs do
  @moduledoc """
  Documentation says why a thing exists and when to call it; it never points
  at test files.

  ## Examples

  Avoid:

        @doc \"\"\"
        The user's memberships. See `test/functional/accounts_test.exs`.
        \"\"\"
        def memberships(user), do: ...

  Prefer:

        @doc "The user's memberships, newest first."
        def memberships(user), do: ...

  A test path in a doc has to be kept in step with the files on every
  rename, and the reader gets nothing from it: the tests are found by the
  function's name and module. The same holds for `@moduledoc` and
  `@typedoc`.

  The check reports a `@doc`, `@moduledoc` or `@typedoc` whose literal
  string mentions a path under `test/`, such as
  `test/functional_web/api/membership_test.exs` or `test/support/foo.ex`,
  at the start of the doc or after any character that is not part of a
  path. A `test/` string anywhere else, and a doc built from a variable or
  an interpolation, are not reported.

  ## Options

  This check takes no options.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoTestPathsInDocs, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    explanations: [check: @moduledoc]

  @doc_attributes [:doc, :moduledoc, :typedoc]
  @path ~r{(?:\A|[^A-Za-z0-9_./-])(test/[A-Za-z0-9_./-]+)}
  @message "Docs say why, never where the tests are: remove the test path from the doc."

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = Credo.SourceFile.ast(source_file)

    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:@, meta, [{attribute, _meta2, [value]}]} = node, issues
        when attribute in @doc_attributes ->
          {node, doc_issues(value, meta, issue_meta) ++ issues}

        node, issues ->
          {node, issues}
      end)

    Enum.sort_by(issues, & &1.line_no)
  end

  defp doc_issues(value, meta, issue_meta) when is_binary(value),
    do: path_issues(value, meta, issue_meta)

  defp doc_issues(_value, _meta, _issue_meta), do: []

  defp path_issues(doc, meta, issue_meta) do
    for path <- Regex.scan(@path, doc, capture: :all_but_first) do
      path = hd(path)
      path = String.replace(path, ~r{[.,;:!?'")\]]+\z}, "")

      format_issue(issue_meta,
        message: @message,
        trigger: path,
        line_no: meta[:line]
      )
    end
  end
end
