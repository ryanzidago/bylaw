defmodule Bylaw.Credo.Check.HEEx.NoIndirectAssignAccess do
  @moduledoc """
  Discourages indirect access to the special HEEx `assigns` variable.

  Avoid:

      ~H"<h1>{Map.get(assigns, :title)}</h1>"

      ~H"<h1>{assigns[:title]}</h1>"

  Initialize the assign before rendering and access it directly:

      ~H"<h1>{@title}</h1>"

  Direct access makes the template's inputs visible and requires missing values
  to be handled at the rendering boundary. This check reports literal keys in
  both two- and three-argument `Map.get` calls, as well as bracket access. It
  ignores dynamic keys because they cannot be safely rewritten to direct HEEx
  assign access.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources`.

  Configure this check with an empty option list:

      {Bylaw.Credo.Check.HEEx.NoIndirectAssignAccess, []}
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:web],
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @message "Avoid indirect access to HEEx assigns. Initialize the assign before rendering and access it directly with `@key`."

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tokens/1)
    |> Enum.flat_map(&issues_for_token(&1, issue_meta))
  end

  defp issues_for_token(%Heex.Expression{} = expression, issue_meta) do
    issues_for_expression(expression.source, expression.line, expression.column, "{", issue_meta)
  end

  defp issues_for_token(%Heex.Tag{attrs: attrs}, issue_meta) do
    Enum.flat_map(attrs, fn
      %{value: {:expr, source, meta}} = attr ->
        line = meta[:line] || attr.line
        column = meta[:column] || attr.column
        issues_for_expression(source, line, column, "", issue_meta)

      _attr ->
        []
    end)
  end

  defp issues_for_token(_token, _issue_meta), do: []

  defp issues_for_expression(source, line, column, trigger_prefix, issue_meta) do
    case Code.string_to_quoted(source, columns: true) do
      {:ok, ast} ->
        {_ast, issues} =
          Macro.prewalk(ast, [], &collect_issue(&1, &2, line, column, trigger_prefix, issue_meta))

        Enum.reverse(issues)

      _error ->
        []
    end
  end

  defp collect_issue(node, issues, line, column, trigger_prefix, issue_meta) do
    case violation(node) do
      {:map_get, meta} ->
        {node, [issue(issue_meta, node, line, column, trigger_prefix, meta) | issues]}

      {:bracket, meta} ->
        {node, [issue(issue_meta, node, line, column, trigger_prefix, meta) | issues]}

      nil ->
        {node, issues}
    end
  end

  defp violation(
         {{:., _dot_meta, [{:__aliases__, alias_meta, [:Map]}, :get]}, _call_meta,
          [assigns, key | rest]}
       ) do
    if Enum.count(rest) in [0, 1] and assigns_variable?(assigns) and is_atom(key) do
      {:map_get, alias_meta}
    end
  end

  defp violation({{:., _dot_meta, [Access, :get]}, _call_meta, [assigns, key]}) do
    if assigns_variable?(assigns) and is_atom(key) do
      {:bracket, assigns_meta(assigns)}
    end
  end

  defp violation(_node), do: nil

  defp assigns_variable?({:assigns, _meta, context}) when is_atom(context) or is_nil(context),
    do: true

  defp assigns_variable?(_node), do: false

  defp assigns_meta({:assigns, meta, _context}), do: meta

  defp issue(issue_meta, node, expression_line, expression_column, trigger_prefix, meta) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: trigger_prefix <> Macro.to_string(node),
      line_no: expression_line + (meta[:line] || 1) - 1,
      column: expression_column + (meta[:column] || 1) - 1
    )
  end
end
