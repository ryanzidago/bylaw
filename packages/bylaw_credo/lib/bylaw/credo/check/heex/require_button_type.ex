defmodule Bylaw.Credo.Check.HEEx.RequireButtonType do
  @moduledoc """
  Requires static HEEx/HTML button tags to define a `type` attribute.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Bad

      ~H\"\"\"
      <button>Open menu</button>
      \"\"\"

  ## Good

      ~H\"\"\"
      <button type="button">Open menu</button>
      <button type="submit">Save</button>
      <button type={@type}>Continue</button>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Buttons in HEEx templates should always define `type`. HTML buttons
      default to `type="submit"` inside forms, which can cause accidental
      submissions for buttons intended to run client-side actions.
      """
    ]

  alias Bylaw.Credo.Heex

  @message "Buttons must define an explicit type attribute."

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.filter(&missing_type?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp missing_type?(%Heex.Tag{type: :tag, name: "button"} = tag) do
    not Heex.has_attr?(tag, "type") and not Heex.has_attr?(tag, :root)
  end

  defp missing_type?(_tag), do: false

  defp issue_for(issue_meta, %Heex.Tag{} = tag) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "<button",
      line_no: tag.line,
      column: tag.column
    )
  end
end
