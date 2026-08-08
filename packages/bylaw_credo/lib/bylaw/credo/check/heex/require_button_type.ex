defmodule Bylaw.Credo.Check.HEEx.RequireButtonType do
  @moduledoc """
  Requires static HEEx/HTML button tags to define a `type` attribute.

  ## Examples

  Avoid:

        ~H\"\"\"
        <button>Open menu</button>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <button type="button">Open menu</button>
        <button type="submit">Save</button>
        <button type={@type}>Continue</button>
        \"\"\"


  A button inside a form defaults to submitting that form when its intent is
  not explicit. Declaring `type` prevents menu, cancel, and other action
  buttons from accidentally triggering submission as the form evolves.
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
          {Bylaw.Credo.Check.HEEx.RequireButtonType, []}
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

  @message "Buttons must define an explicit type attribute."
  @doc false
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
