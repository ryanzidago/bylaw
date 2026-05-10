defmodule Bylaw.Credo.Check.HEEx.NoJavascriptHref do
  @moduledoc """
  Forbids static HEEx/HTML link `href` attributes that use `javascript:`.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  Avoid:

        ~H\"\"\"
        <a href="javascript:alert('x')">Delete</a>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <a href="/account">Account</a>
        <a href={@href}>Dynamic link</a>
        <button phx-click="delete">Delete</button>
        \"\"\"

  ## Notes

  Embedded `~H` templates in `.ex` and `.exs` files are checked by Credo's normal source traversal. Standalone `.html.heex` templates are checked when `Bylaw.Credo.Plugin.HEExSources` is enabled in `.credo.exs`.

  This check uses static HEEx token analysis, so it reports only patterns visible in the template source.

  ## Options

  This check has no check-specific options. Configure it with an empty option list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.NoJavascriptHref, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @message "Links must not use javascript: href values."
  @doc false
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

  defp javascript_href?(%{name: name, value: {:string, value, _meta}}) when is_binary(name) do
    String.downcase(name) == "href" and javascript_href_value?(value)
  end

  defp javascript_href?(_attr), do: false

  defp javascript_href_value?(value) do
    value
    |> String.trim_leading()
    |> String.downcase()
    |> String.starts_with?("javascript:")
  end

  defp issue_for(issue_meta, %{name: name, line: line, column: column}) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: name,
      line_no: line,
      column: column
    )
  end
end
