defmodule Bylaw.Credo.Check.HEEx.PreferNativeInteractiveElement do
  @moduledoc """
  Prefers native interactive elements over clickable static HEEx/HTML tags.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  Avoid:

        ~H\"\"\"
        <div phx-click="save">Save</div>
        <span phx-click="open">Open</span>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <button type="button" phx-click="save">Save</button>
        <a href={~p"/settings"}>Settings</a>
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
          {Bylaw.Credo.Check.HEEx.PreferNativeInteractiveElement, []}
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

  @message "Prefer a native interactive element, such as button or a, over a clickable div or span."
  @static_non_interactive_tags ["div", "span"]
  @keyboard_attrs [
    "phx-keydown",
    "phx-keyup",
    "phx-window-keydown",
    "phx-window-keyup",
    "onkeydown",
    "onkeyup"
  ]
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.filter(&clickable_static_non_interactive?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp clickable_static_non_interactive?(%Heex.Tag{type: :tag, name: name} = tag)
       when name in @static_non_interactive_tags do
    Heex.has_attr?(tag, "phx-click") and not Heex.has_attr?(tag, :root) and
      not accessible_widget_pattern?(tag)
  end

  defp clickable_static_non_interactive?(_tag), do: false

  defp accessible_widget_pattern?(%Heex.Tag{} = tag) do
    Heex.has_attr?(tag, "role") and Heex.has_attr?(tag, "tabindex") and keyboard_handler?(tag)
  end

  defp keyboard_handler?(%Heex.Tag{} = tag) do
    Enum.any?(@keyboard_attrs, &Heex.has_attr?(tag, &1))
  end

  defp issue_for(issue_meta, %Heex.Tag{} = tag) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "<#{tag.name}",
      line_no: tag.line,
      column: tag.column
    )
  end
end
