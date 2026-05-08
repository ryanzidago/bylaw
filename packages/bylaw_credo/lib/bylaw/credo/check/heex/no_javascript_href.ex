defmodule Bylaw.Credo.Check.HEEx.NoJavascriptHref do
  @moduledoc """
  Forbids static HEEx/HTML link `href` attributes that use `javascript:`.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Bad

      ~H\"\"\"
      <a href="javascript:alert('x')">Delete</a>
      \"\"\"

  ## Good

      ~H\"\"\"
      <a href="/account">Account</a>
      <a href={@href}>Dynamic link</a>
      <button phx-click="delete">Delete</button>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Links with `javascript:` hrefs are poor for accessibility, predictable
      navigation, copy/open behavior, and security posture. Use regular links
      for navigation and buttons or LiveView events for actions.
      """
    ]

  alias Bylaw.Credo.Heex

  @message "Links must not use javascript: href values."

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.flat_map(&javascript_href_attrs/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp javascript_href_attrs(%Heex.Tag{type: :tag, name: "a", attrs: attrs}) do
    Enum.filter(attrs, &javascript_href?/1)
  end

  defp javascript_href_attrs(_tag), do: []

  defp javascript_href?(%{name: "href", value: {:string, value, _meta}}) do
    value
    |> String.trim_leading()
    |> String.downcase()
    |> String.starts_with?("javascript:")
  end

  defp javascript_href?(_attr), do: false

  defp issue_for(issue_meta, %{line: line, column: column}) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "href",
      line_no: line,
      column: column
    )
  end
end
