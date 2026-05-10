defmodule Bylaw.Credo.Check.HEEx.RequireLinkHref do
  @moduledoc """
  Requires static HEEx/HTML anchor tags to define an `href` attribute.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  Avoid:

        ~H\"\"\"
        <a>Read more</a>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <a href="/articles">Read more</a>
        <a href={@path}>Read more</a>
        <a {@attrs}>Read more</a>
        \"\"\"

  ## Notes

  Embedded `~H` templates in `.ex` and `.exs` files are checked by Credo's normal source traversal. Standalone `.html.heex` templates are checked when `Bylaw.Credo.Plugin.HEExSources` is enabled in `.credo.exs`.

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is available. Add `phoenix_live_view` to applications that enable this check.

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
          {Bylaw.Credo.Check.HEEx.RequireLinkHref, []}
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

  @message "Anchor tags must define an href attribute. Use a button for actions."
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.filter(&missing_href?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp missing_href?(%Heex.Tag{type: :tag, name: "a"} = tag) do
    not Heex.has_attr?(tag, "href") and not Heex.has_attr?(tag, :root)
  end

  defp missing_href?(_tag), do: false

  defp issue_for(issue_meta, %Heex.Tag{} = tag) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "<a",
      line_no: tag.line,
      column: tag.column
    )
  end
end
