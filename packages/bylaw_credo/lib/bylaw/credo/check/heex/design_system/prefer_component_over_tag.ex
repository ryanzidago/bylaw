defmodule Bylaw.Credo.Check.HEEx.DesignSystem.PreferComponentOverTag do
  @moduledoc """
  Forbids raw HTML tags that have a design-system component.

  ## Examples

  Avoid:

      ~H\"\"\"
      <button type="button" class="font-mono uppercase">Save</button>
      <input type="text" name="title" />
      \"\"\"

  Prefer:

      ~H\"\"\"
      <.button type="button">Save</.button>
      <.input field={@form[:title]} />
      \"\"\"

  A hand-rolled button or input copies the component's classes, or invents its
  own, and drifts from the design system the next time the component changes.
  Rendering the component keeps its markup and styling in one place.

  Only raw HTML tags named in `:tags` are reported; components and slots are
  left alone. The modules that define the components still render the raw
  tags, so exclude them with Credo's per-check `files` param, which Credo's
  runner applies before running the check, as in the example below.
  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.DesignSystem.PreferComponentOverTag,
           [
             tags: [button: ".button", input: ".input", select: ".input", textarea: ".input"],
             files: %{excluded: ["lib/my_app_web/components/"]}
           ]}
        ]
      }
    ]
  }
  ```

  - `:tags` - A keyword list or map from a raw HTML tag name to the component to use instead, written as it appears in markup; a local component's leading dot is optional (default: none, so nothing is reported).

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs` with the `:tags`
  your design system provides components for.

  ## Notes

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is available. Add `phoenix_live_view` to applications that enable this check.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    tags: [:web, :design_system],
    param_defaults: [tags: []],
    explanations: [
      check: @moduledoc,
      params: [
        tags:
          "A keyword list or map from a raw HTML tag name to the component to use instead, written as it appears in markup; a local component's leading dot is optional (default: none, so nothing is reported)."
      ]
    ]

  alias Bylaw.Credo.Heex

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    components =
      params
      |> Params.get(:tags, __MODULE__)
      |> Map.new(fn {tag, component} -> {to_string(tag), component_label(component)} end)

    if map_size(components) == 0 do
      []
    else
      source_file
      |> Heex.templates()
      |> Enum.flat_map(&Heex.tags/1)
      |> Enum.filter(&(&1.type == :tag and Map.has_key?(components, &1.name)))
      |> Enum.map(&issue_for(issue_meta, &1, Map.fetch!(components, &1.name)))
    end
  end

  defp component_label(component) do
    case to_string(component) do
      "." <> _name = local ->
        "<#{local}>"

      name ->
        if name =~ ~r/^[A-Z]/ do
          "<#{name}>"
        else
          "<.#{name}>"
        end
    end
  end

  defp issue_for(issue_meta, %Heex.Tag{name: name, line: line, column: column}, component) do
    format_issue(
      issue_meta,
      message:
        "Use the #{component} component instead of a raw <#{name}> tag, so the design system owns its markup.",
      trigger: "<#{name}",
      line_no: line,
      column: column
    )
  end
end
