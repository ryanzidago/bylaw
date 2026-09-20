defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass do
  @moduledoc """
  Forbids class attributes on HEEx function components.

  ## Examples

  Avoid:

      ~H\"\"\"
      <.button class="px-4 py-2">Save</.button>
      <Layouts.app class="mb-14">Content</Layouts.app>
      \"\"\"

  Prefer:

      ~H\"\"\"
      <.button size="lg">Save</.button>
      <Layouts.app>Content</Layouts.app>
      \"\"\"

  A component that accepts a class attribute has no styling contract. Every
  caller can restyle it, and the component cannot tell which of its own classes
  a caller meant to replace. Props such as `size`, `variant` or `position` name
  the choices the component supports and keep its markup in one place.

  Plain HTML tags and slot tags are left alone, and both `class="..."` and
  `class={...}` are reported. Components whose class attribute is their
  documented interface, such as a framework's link or icon, belong in
  `:excluded_components`. Embedded `~H` templates are checked during normal
  Credo runs over Elixir files. Standalone `.html.heex` templates require
  enabling `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass,
           [
             excluded_components: [".link", ".form", "Layouts.app"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:excluded_components` - Component names whose class attribute is allowed, written as they appear in markup, with an optional leading dot (default: none).

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass, []}
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
    category: :design,
    tags: [:web, :design_system],
    param_defaults: [excluded_components: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_components:
          "Component names whose class attribute is allowed, written as they appear in markup, with an optional leading dot (default: none)."
      ]
    ]

  alias Bylaw.Credo.Heex

  @message "Give the component a semantic prop such as size, variant, or position instead of a class attribute."
  @component_types [:local_component, :remote_component]

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    excluded_components =
      params
      |> Params.get(:excluded_components, __MODULE__)
      |> MapSet.new(&component_name/1)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.flat_map(&class_attrs(&1, excluded_components))
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp class_attrs(%Heex.Tag{type: type, name: name, attrs: attrs} = tag, excluded_components)
       when type in @component_types do
    if MapSet.member?(excluded_components, component_name(name)) do
      []
    else
      attrs
      |> Enum.filter(&class_attr?/1)
      |> Enum.map(&Map.put(&1, :tag, tag))
    end
  end

  defp class_attrs(_tag, _excluded_components), do: []

  defp class_attr?(%{name: name}) when is_binary(name) do
    String.downcase(name) == "class"
  end

  defp class_attr?(_attr), do: false

  defp component_name("." <> name), do: name
  defp component_name(name), do: name

  defp issue_for(issue_meta, %{tag: %Heex.Tag{} = tag, name: name} = attr) do
    format_issue(
      issue_meta,
      message: "#{@message} Component: #{component_label(tag)}.",
      trigger: name,
      line_no: attr.line || tag.line,
      column: attr.column || tag.column
    )
  end

  defp component_label(%Heex.Tag{type: :local_component, name: name}), do: "<.#{name}>"
  defp component_label(%Heex.Tag{type: :remote_component, name: name}), do: "<#{name}>"
end
