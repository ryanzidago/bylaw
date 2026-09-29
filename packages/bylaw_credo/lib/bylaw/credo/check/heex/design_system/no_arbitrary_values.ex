defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitraryValues do
  @moduledoc """
  Forbids Tailwind arbitrary values in HEEx class attributes.

  ## Examples

  Avoid:

      ~H\"\"\"
      <div class="w-[430px] grid-cols-[34px_minmax(0,1fr)] [mask-type:luminance]"></div>
      <div class={["p-4", @open && "h-[30px]"]}></div>
      \"\"\"

  Prefer:

      ~H\"\"\"
      <div class="w-panel grid-cols-2 rule-row"></div>
      <div class={["p-4", @open && "h-8"]}></div>
      \"\"\"

  An arbitrary value such as `w-[430px]` bypasses the design system's theme.
  Each one is a new size, colour or layout that no token names, so visual drift
  goes unnoticed and cannot be adjusted in one place. Add a token to the theme,
  or give a one-off layout a named CSS rule, instead.

  Only the utility is checked. Arbitrary variants such as
  `has-[textarea:focus]:bg-fill` or `[&>*]:p-2` select elements rather than set
  values, and CSS variable shorthand such as `w-(--measure)` refers to a
  token, so both are allowed. Static `class="..."` attributes and the string
  literals inside dynamic `class={...}` expressions are checked, on HTML tags
  and components alike.

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
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitraryValues, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    tags: [:web, :design_system],
    explanations: [
      check: """
      HEEx templates should use design-system tokens or named CSS rules instead
      of Tailwind arbitrary values. Arbitrary values bypass the theme, so
      visual drift goes unnoticed and cannot be adjusted in one place.
      """
    ]

  alias Bylaw.Credo.Heex

  @class_attr "class"
  @message "Use a design-system token or a named CSS rule instead of an arbitrary Tailwind value."

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.flat_map(&class_attrs/1)
    |> Enum.flat_map(&arbitrary_classes/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp class_attrs(%Heex.Tag{attrs: attrs}) do
    Enum.filter(attrs, &class_attr?/1)
  end

  defp class_attr?(%{name: name}) when is_binary(name), do: String.downcase(name) == @class_attr
  defp class_attr?(_attr), do: false

  defp arbitrary_classes(%{value: value} = attr) do
    value
    |> class_strings()
    |> Enum.flat_map(&String.split/1)
    |> Enum.filter(&arbitrary_class?/1)
    |> Enum.map(&Map.put(attr, :arbitrary_value, &1))
  end

  defp class_strings({:string, value, _meta}) when is_binary(value), do: [value]

  defp class_strings({:expr, source, _meta}) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        ast
        |> Macro.prewalk([], &collect_string/2)
        |> elem(1)
        |> Enum.reverse()

      _error ->
        []
    end
  end

  defp class_strings(_value), do: []

  defp collect_string(string, strings) when is_binary(string), do: {string, [string | strings]}
  defp collect_string(ast, strings), do: {ast, strings}

  defp arbitrary_class?(class) do
    class
    |> utility()
    |> String.contains?("[")
  end

  # The utility is the last `:`-separated segment outside brackets; everything
  # before it is variants, which may use arbitrary selectors.
  defp utility(class) do
    {utility, _depth} =
      class
      |> String.graphemes()
      |> Enum.reduce({"", 0}, &split_variant/2)

    utility
  end

  defp split_variant(":", {_current, 0}), do: {"", 0}
  defp split_variant("[", {current, depth}), do: {current <> "[", depth + 1}
  defp split_variant("]", {current, depth}), do: {current <> "]", max(depth - 1, 0)}
  defp split_variant(char, {current, depth}), do: {current <> char, depth}

  defp issue_for(issue_meta, %{name: name, arbitrary_value: value, line: line, column: column}) do
    format_issue(
      issue_meta,
      message: "#{@message} Arbitrary value: #{inspect(value)}.",
      trigger: name,
      line_no: line,
      column: column
    )
  end
end
