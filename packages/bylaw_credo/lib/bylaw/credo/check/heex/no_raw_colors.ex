defmodule Bylaw.Credo.Check.HEEx.NoRawColors do
  @moduledoc """
  Forbids raw color literals in static HEEx/HTML attributes.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  Configure `allowed_colors` with design-system tokens or classes that should
  remain valid in static attributes.

  ## Bad

      ~H\"\"\"
      <div class="text-[#ff0000] bg-white" style="color: rgb(255 0 0)"></div>
      <svg fill="#fff" stroke="black"></svg>
      \"\"\"

  ## Good

      ~H\"\"\"
      <div class="text-primary bg-surface border-default" style="color: var(--color-primary)"></div>
      <svg fill="currentColor" stroke={@stroke}></svg>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [allowed_colors: []],
    explanations: [
      check: """
      HEEx templates should use design-system color tokens instead of raw color
      literals. Raw values make theme changes, contrast audits, and visual
      consistency harder to maintain.
      """,
      params: [
        allowed_colors:
          "List of design-system color tokens or static classes allowed in checked attributes."
      ]
    ]

  alias Bylaw.Credo.Heex

  @checked_attrs ~w(class style color fill stroke bgcolor)
  @color_functions ~w(rgb rgba hsl hsla oklch oklab)
  @named_colors ~w(
    black white red blue gray grey green yellow purple pink orange indigo violet
    cyan teal lime amber rose
  )
  @tailwind_color_prefixes ~w(
    text bg border decoration accent caret fill stroke from via to outline ring
    divide placeholder shadow
  )
  @message "Use a design-system color token instead of a raw color literal."

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    allowed_colors = params |> Params.get(:allowed_colors, __MODULE__) |> MapSet.new()

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.flat_map(&raw_color_attrs(&1, allowed_colors))
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp raw_color_attrs(%Heex.Tag{type: :tag, attrs: attrs}, allowed_colors) do
    attrs
    |> Enum.filter(&checked_static_attr?/1)
    |> Enum.flat_map(&raw_colors_in_attr(&1, allowed_colors))
  end

  defp raw_color_attrs(_tag, _allowed_colors), do: []

  defp checked_static_attr?(%{name: name, value: {:string, value, _meta}})
       when is_binary(name) and is_binary(value) do
    attr_name(name) in @checked_attrs
  end

  defp checked_static_attr?(_attr), do: false

  defp raw_colors_in_attr(%{name: name, value: {:string, value, _meta}} = attr, allowed_colors) do
    value
    |> raw_colors_for_attr(attr_name(name), allowed_colors)
    |> Enum.map(&Map.put(attr, :raw_color, &1))
  end

  defp raw_colors_for_attr(value, "class", allowed_colors) do
    value
    |> String.split()
    |> Enum.reject(&allowed_color?(&1, allowed_colors))
    |> Enum.filter(&raw_class_color?/1)
  end

  defp raw_colors_for_attr(value, _attr_name, allowed_colors) do
    if allowed_color?(String.trim(value), allowed_colors) do
      []
    else
      raw_colors_in_value(value)
    end
  end

  defp raw_class_color?(class) do
    utility = class |> String.split(":") |> List.last()

    raw_arbitrary_color?(utility) or raw_tailwind_named_color?(utility) or
      exact_named_color?(utility)
  end

  defp raw_arbitrary_color?(utility) do
    case Regex.run(~r/\[(?<value>.+)\]/, utility, capture: ["value"]) do
      [value] -> raw_colors_in_value(value) != []
      nil -> false
    end
  end

  defp raw_tailwind_named_color?(utility) do
    Enum.any?(@tailwind_color_prefixes, fn prefix ->
      Regex.match?(~r/^#{prefix}-(?:#{named_color_pattern()})(?:-\d{2,3})?(?:\/\d+)?$/i, utility)
    end)
  end

  defp raw_colors_in_value(value) do
    []
    |> maybe_add_regex_matches(value, ~r/#(?:[0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})(?![0-9a-f])/i)
    |> maybe_add_regex_matches(value, ~r/(?:#{function_pattern()})\s*\([^)]*\)/i)
    |> maybe_add_regex_matches(value, ~r/\b(?:#{named_color_pattern()})\b/i)
    |> Enum.uniq()
  end

  defp maybe_add_regex_matches(matches, value, regex) do
    regex
    |> Regex.scan(value)
    |> Enum.map(&List.first/1)
    |> Kernel.++(matches)
  end

  defp exact_named_color?(value) do
    String.downcase(value) in @named_colors
  end

  defp allowed_color?(value, allowed_colors) do
    MapSet.member?(allowed_colors, value)
  end

  defp attr_name(name) do
    String.downcase(name)
  end

  defp function_pattern do
    Enum.join(@color_functions, "|")
  end

  defp named_color_pattern do
    Enum.join(@named_colors, "|")
  end

  defp issue_for(issue_meta, %{name: name, raw_color: raw_color, line: line, column: column}) do
    format_issue(
      issue_meta,
      message: "#{@message} Raw color: #{inspect(raw_color)}.",
      trigger: name,
      line_no: line,
      column: column
    )
  end
end
