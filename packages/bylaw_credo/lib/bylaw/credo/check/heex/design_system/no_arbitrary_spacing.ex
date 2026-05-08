defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacing do
  @moduledoc """
  Forbids raw pixel spacing values in static HEEx/HTML attributes.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Bad

      ~H\"\"\"
      <div class="m-[18px] p-[22px] gap-[13px]" style="margin: 18px"></div>
      \"\"\"

  ## Good

      ~H\"\"\"
      <div class="m-4 p-6 gap-3" style="margin: var(--space-4)"></div>
      <div class={@class} style={@style}></div>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      HEEx templates should use design-system spacing tokens instead of raw
      pixel values. One-off spacing values make layouts harder to keep visually
      consistent and harder to adjust across breakpoints or themes.
      """
    ]

  alias Bylaw.Credo.Heex

  @class_attr "class"
  @style_attr "style"
  @message "Use a design-system spacing token instead of a raw pixel spacing value."
  @tailwind_spacing_prefixes ~w(m mx my mt mr mb ml p px py pt pr pb pl gap gap-x gap-y)

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.flat_map(&raw_spacing_attrs/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp raw_spacing_attrs(%Heex.Tag{attrs: attrs}) do
    attrs
    |> Enum.filter(&static_attr?/1)
    |> Enum.flat_map(&raw_spacing_in_attr/1)
  end

  defp static_attr?(%{name: name, value: {:string, value, _meta}})
       when is_binary(name) and is_binary(value) do
    attr_name(name) in [@class_attr, @style_attr]
  end

  defp static_attr?(_attr), do: false

  defp raw_spacing_in_attr(%{name: name, value: {:string, value, _meta}} = attr) do
    value
    |> raw_spacing_for_attr(attr_name(name))
    |> Enum.map(&Map.put(attr, :raw_spacing, &1))
  end

  defp raw_spacing_for_attr(value, @class_attr) do
    value
    |> String.split()
    |> Enum.filter(&raw_spacing_class?/1)
  end

  defp raw_spacing_for_attr(value, @style_attr) do
    value
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&raw_spacing_style_declaration?/1)
  end

  defp raw_spacing_class?(class) do
    class
    |> base_utility()
    |> raw_spacing_utility?()
  end

  defp base_utility(class) do
    class
    |> String.split(":")
    |> List.last()
    |> String.trim_leading("-")
  end

  defp raw_spacing_utility?(utility) do
    Enum.any?(@tailwind_spacing_prefixes, fn prefix ->
      case Regex.run(~r/^#{Regex.escape(prefix)}-\[(?<value>.*)\]$/i, utility, capture: ["value"]) do
        [value] -> raw_px_value?(value)
        nil -> false
      end
    end)
  end

  defp raw_spacing_style_declaration?(declaration) do
    case String.split(declaration, ":", parts: 2) do
      [property, value] ->
        spacing_property?(property) and raw_px_value?(value)

      _other ->
        false
    end
  end

  defp spacing_property?(property) do
    property
    |> String.trim()
    |> String.downcase()
    |> then(&Regex.match?(~r/^(?:margin|padding)(?:$|-)/, &1))
  end

  defp raw_px_value?(value) do
    Regex.match?(~r/(?:^|[^[:alnum:]_-])-?\d+(?:\.\d+)?px\b/i, value)
  end

  defp attr_name(name) do
    String.downcase(name)
  end

  defp issue_for(issue_meta, %{name: name, raw_spacing: raw_spacing, line: line, column: column}) do
    format_issue(
      issue_meta,
      message: "#{@message} Raw spacing: #{inspect(raw_spacing)}.",
      trigger: name,
      line_no: line,
      column: column
    )
  end
end
