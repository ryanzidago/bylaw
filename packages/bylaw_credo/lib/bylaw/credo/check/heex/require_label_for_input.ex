defmodule Bylaw.Credo.Check.HEEx.RequireLabelForInput do
  @moduledoc """
  Requires static HEEx/HTML form controls to have an accessible name.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Bad

      ~H\"\"\"
      <input id="email" name="email">
      <select id="role"></select>
      <textarea id="bio"></textarea>
      \"\"\"

  ## Good

      ~H\"\"\"
      <label for="email">Email</label>
      <input id="email" name="email">
      <select aria-label="Role"></select>
      <textarea aria-labelledby="bio-label"></textarea>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @control_tags ~w(input select textarea)
  @message "Form controls must have an accessible name."

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&issues_for_template(issue_meta, &1))
  end

  defp issues_for_template(issue_meta, template) do
    tags = Heex.tags(template)
    labelled_ids = labelled_ids(tags)

    tags
    |> Enum.filter(&missing_accessible_name?(&1, labelled_ids))
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp labelled_ids(tags) do
    tags
    |> Enum.filter(&label_tag?/1)
    |> Enum.flat_map(&static_attr_values(&1, "for"))
    |> MapSet.new()
  end

  defp label_tag?(%Heex.Tag{type: :tag, name: "label"}), do: true
  defp label_tag?(_tag), do: false

  defp missing_accessible_name?(%Heex.Tag{type: :tag, name: name} = tag, labelled_ids)
       when name in @control_tags do
    not dynamic_control?(tag) and not hidden_input?(tag) and not has_aria_name?(tag) and
      not statically_labelled?(tag, labelled_ids)
  end

  defp missing_accessible_name?(_tag, _labelled_ids), do: false

  defp dynamic_control?(%Heex.Tag{name: "input"} = tag) do
    dynamic_identity?(tag) or dynamic_attr?(tag, "type")
  end

  defp dynamic_control?(%Heex.Tag{} = tag) do
    dynamic_identity?(tag)
  end

  defp dynamic_identity?(%Heex.Tag{} = tag) do
    Heex.has_attr?(tag, :root) or dynamic_attr?(tag, "id")
  end

  defp hidden_input?(%Heex.Tag{name: "input"} = tag) do
    tag
    |> static_attr_values("type")
    |> Enum.any?(&(String.downcase(&1) == "hidden"))
  end

  defp hidden_input?(_tag), do: false

  defp has_aria_name?(%Heex.Tag{} = tag) do
    has_accessible_name_attr?(tag, "aria-label") or
      has_accessible_name_attr?(tag, "aria-labelledby")
  end

  defp statically_labelled?(%Heex.Tag{} = tag, labelled_ids) do
    tag
    |> static_attr_values("id")
    |> Enum.any?(&MapSet.member?(labelled_ids, &1))
  end

  defp static_attr_values(%Heex.Tag{attrs: attrs}, name) do
    attrs
    |> Enum.filter(&(&1.name == name))
    |> Enum.flat_map(&static_attr_value/1)
  end

  defp static_attr_value(%{value: {:string, value, _meta}}), do: [value]
  defp static_attr_value(_attr), do: []

  defp has_accessible_name_attr?(%Heex.Tag{attrs: attrs}, name) do
    Enum.any?(attrs, &accessible_name_attr?(&1, name))
  end

  defp accessible_name_attr?(%{name: attr_name, value: {:string, value, _meta}}, name)
       when attr_name == name do
    String.trim(value) != ""
  end

  defp accessible_name_attr?(%{name: attr_name, value: {:expr, _expr, _meta}}, name)
       when attr_name == name,
       do: true

  defp accessible_name_attr?(_attr, _name), do: false

  defp dynamic_attr?(%Heex.Tag{attrs: attrs}, name) do
    Enum.any?(attrs, &(&1.name == name and match?({:expr, _expr, _meta}, &1.value)))
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
