defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoHexColor do
  @moduledoc """
  Forbids hex colours in the colour attributes of HEEx tags.

  ## Examples

  Avoid:

      ~H\"\"\"
      <svg fill="#0a0a0a"><path stroke="#fff" /></svg>
      \"\"\"

  Prefer:

      ~H\"\"\"
      <svg fill="currentColor"><path stroke="currentColor" /></svg>
      \"\"\"

  A hex colour in markup is a colour no token names. It stays the same in dark
  mode and when the palette changes. Use `currentColor` so the icon takes the
  text colour around it, or a named CSS class that uses a colour token.

  Only the attributes listed in `:attributes` are read, because `#abc` is also
  an anchor in `href="#abc"` and text such as an order number. String literals
  inside dynamic attributes are read too. The `style` attribute is in the
  default list so a custom property cannot carry a hex colour in.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Options

  - `:attributes` - attribute names to read. Defaults to `fill`, `stroke`,
    `color`, `bgcolor`, `stop-color`, `flood-color`, `lighting-color` and `style`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoHexColor, []}
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
    param_defaults: [
      attributes: ~w(fill stroke color bgcolor stop-color flood-color lighting-color style)
    ],
    explanations: [
      check: """
      HEEx templates should not hard-code hex colours. Use currentColor or a
      named CSS class that uses a colour token, so the colour follows the theme.
      """,
      params: [
        attributes: "Attribute names whose values are read for hex colours."
      ]
    ]

  alias Bylaw.Credo.Heex

  @hex ~r/#[0-9a-fA-F]{3,8}\b/
  @message "Use currentColor or a named CSS class that uses a colour token instead of a hex colour."

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    attributes = Params.get(params, :attributes, __MODULE__)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.flat_map(&hex_attrs(&1, attributes))
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp hex_attrs(%Heex.Tag{attrs: attrs}, attributes) do
    attrs
    |> Enum.filter(&read_attr?(&1, attributes))
    |> Enum.flat_map(fn attr ->
      attr.value
      |> strings()
      |> Enum.flat_map(&Regex.scan(@hex, &1))
      |> Enum.map(fn [hex] -> Map.put(attr, :hex, hex) end)
    end)
  end

  defp read_attr?(%{name: name}, attributes) when is_binary(name),
    do: String.downcase(name) in attributes

  defp read_attr?(_attr, _attributes), do: false

  defp strings({:string, value, _meta}) when is_binary(value), do: [value]

  defp strings({:expr, source, _meta}) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} ->
        ast
        |> Macro.prewalk([], fn
          string, acc when is_binary(string) -> {string, [string | acc]}
          ast, acc -> {ast, acc}
        end)
        |> elem(1)

      _error ->
        []
    end
  end

  defp strings(_value), do: []

  defp issue_for(issue_meta, %{name: name, hex: hex, line: line, column: column}) do
    format_issue(
      issue_meta,
      message: "#{@message} Colour: #{inspect(hex)}.",
      trigger: name,
      line_no: line,
      column: column
    )
  end
end
