defmodule Bylaw.Credo.Check.HEEx.RequireLinkText do
  @moduledoc """
  Requires static HEEx/HTML links to have an accessible name.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  Avoid:

        ~H\"\"\"
        <a href="/settings"></a>
        <a href="/settings"><.icon name="settings" /></a>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <a href="/settings">Settings</a>
        <a href="/settings" aria-label="Settings"><.icon name="settings" /></a>
        <a href={@href}>{@label}</a>
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
          {Bylaw.Credo.Check.HEEx.RequireLinkText, []}
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

  @message "Links must have accessible text or an accessible name."
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tokens/1)
    |> missing_link_text_tags()
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp missing_link_text_tags(tokens) do
    tokens
    |> collect_links([])
    |> Enum.reject(&accessible_name?/1)
    |> Enum.map(fn {tag, _children} -> tag end)
  end

  defp collect_links([], links), do: Enum.reverse(links)

  defp collect_links([%Heex.Tag{type: :tag, name: "a", closing: closing} = tag | rest], links) do
    if closing == :self do
      collect_links(rest, add_link(tag, [], links))
    else
      {children, rest} = take_children_until_close(rest, "a", [])

      collect_links(rest, add_link(tag, children, links))
    end
  end

  defp collect_links([_token | rest], links), do: collect_links(rest, links)

  defp add_link(%Heex.Tag{} = tag, children, links) do
    if link_tag?(tag) do
      [{tag, children} | links]
    else
      links
    end
  end

  defp link_tag?(%Heex.Tag{} = tag) do
    Heex.has_attr?(tag, "href") or Heex.has_attr?(tag, :root)
  end

  defp take_children_until_close([], _name, children), do: {Enum.reverse(children), []}

  defp take_children_until_close([%Heex.CloseTag{name: name} | rest], name, children) do
    {Enum.reverse(children), rest}
  end

  defp take_children_until_close([token | rest], name, children) do
    take_children_until_close(rest, name, [token | children])
  end

  defp accessible_name?({%Heex.Tag{} = tag, children}) do
    Heex.has_attr?(tag, :root) or
      non_empty_attr?(tag, "aria-label") or
      non_empty_attr?(tag, "aria-labelledby") or
      Enum.any?(children, &name_content?/1)
  end

  defp name_content?(%Heex.Text{content: content}) do
    String.trim(content) != ""
  end

  defp name_content?(%Heex.Expression{}), do: true

  defp name_content?(%Heex.Tag{type: :tag, name: "img"} = tag) do
    non_empty_attr?(tag, "alt")
  end

  defp name_content?(_token), do: false

  defp non_empty_attr?(%Heex.Tag{attrs: attrs}, name) do
    Enum.any?(attrs, fn attr ->
      attr.name == name and attr_value?(attr.value)
    end)
  end

  defp attr_value?({:string, value, _meta}) do
    String.trim(value) != ""
  end

  defp attr_value?({:expr, _value, _meta}), do: true
  defp attr_value?(value) when is_binary(value), do: String.trim(value) != ""
  defp attr_value?(_value), do: true

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
