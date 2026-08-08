defmodule Bylaw.Credo.Check.HEEx.RequireImageAlt do
  @moduledoc """
  Requires static HEEx/HTML image tags to define an `alt` attribute.

  ## Examples

  Avoid:

        ~H\"\"\"
        <img src="/logo.svg">
        \"\"\"
  Prefer:

        ~H\"\"\"
        <img src="/logo.svg" alt="Company logo">
        <img src="/spacer.svg" alt="">
        <img src={@src} alt={@alt}>
        \"\"\"


  Alternative text gives people who cannot see the image its meaning. An
  explicit empty value is still useful for decorative images because it tells
  assistive technology to skip content that carries no information.
  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

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
          {Bylaw.Credo.Check.HEEx.RequireImageAlt, []}
        ]
      }
    ]
  }
  ```

  ## Notes

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is available. Add `phoenix_live_view` to applications that enable this check.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:web, :accessibility],
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @message "Images must define an alt attribute. Use alt=\"\" for decorative images."
  @doc false
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
