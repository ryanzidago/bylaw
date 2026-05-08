defmodule Bylaw.Credo.Check.HEEx.NoDuplicateStaticIds do
  @moduledoc """
  Forbids duplicate static `id` attributes in HEEx/HTML templates.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  Dynamic `id` values and root attributes are ignored because their final DOM
  IDs cannot be proven statically.

  ## Bad

      ~H\"\"\"
      <section id="profile">
        <div id="profile"></div>
      </section>
      \"\"\"

  ## Good

      ~H\"\"\"
      <section id="profile">
        <div id="profile-details"></div>
        <div id={@dynamic_id}></div>
      </section>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Static DOM IDs in the same HEEx source should be unique. Duplicate IDs
      break labels, ARIA references, fragment links, selectors, JavaScript, and
      LiveView targeting.
      """
    ]

  alias Bylaw.Credo.Heex

  @message "Static DOM id values must be unique within a HEEx source."

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&duplicate_ids_in_template/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp duplicate_ids_in_template(template) do
    template
    |> Heex.tags()
    |> static_ids()
    |> duplicate_ids()
  end

  defp static_ids(tags) do
    tags
    |> Enum.filter(&html_tag?/1)
    |> Enum.flat_map(fn tag ->
      tag.attrs
      |> Enum.filter(&static_id?/1)
      |> Enum.map(&Map.put(&1, :tag, tag))
    end)
  end

  defp html_tag?(%Heex.Tag{type: :tag}), do: true
  defp html_tag?(_tag), do: false

  defp static_id?(%{name: "id", value: {:string, value, _meta}}) when is_binary(value), do: true
  defp static_id?(_attr), do: false

  defp duplicate_ids(static_ids) do
    {_seen, duplicates} =
      Enum.reduce(static_ids, {%{}, []}, fn %{value: {:string, value, _meta}} = attr,
                                            {seen, duplicates} ->
        if Map.has_key?(seen, value) do
          {seen, [attr | duplicates]}
        else
          {Map.put(seen, value, attr), duplicates}
        end
      end)

    Enum.reverse(duplicates)
  end

  defp issue_for(issue_meta, %{tag: %Heex.Tag{} = tag, value: {:string, value, _meta}} = attr) do
    format_issue(
      issue_meta,
      message: "#{@message} Duplicate id: #{inspect(value)}.",
      trigger: ~s(id="#{value}"),
      line_no: attr.line || tag.line,
      column: attr.column || tag.column
    )
  end
end
