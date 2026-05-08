defmodule Bylaw.Credo.Check.HEEx.RequireImageAlt do
  @moduledoc """
  Requires static HEEx/HTML image tags to define an `alt` attribute.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Bad

      ~H\"\"\"
      <img src="/logo.svg">
      \"\"\"

  ## Good

      ~H\"\"\"
      <img src="/logo.svg" alt="Company logo">
      <img src="/spacer.svg" alt="">
      <img src={@src} alt={@alt}>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @message "Images must define an alt attribute. Use alt=\"\" for decorative images."

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.filter(&missing_alt?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp missing_alt?(%Heex.Tag{type: :tag, name: "img"} = tag) do
    not Heex.has_attr?(tag, "alt") and not Heex.has_attr?(tag, :root)
  end

  defp missing_alt?(_tag), do: false

  defp issue_for(issue_meta, %Heex.Tag{} = tag) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "<img",
      line_no: tag.line,
      column: tag.column
    )
  end
end
