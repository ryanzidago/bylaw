defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStyle do
  @moduledoc """
  Forbids `style` attributes in HEEx, except ones that only set CSS custom properties.

  ## Examples

  Avoid:

      ~H\"\"\"
      <div style="padding: 13px; color: red"></div>
      <div style={@style}></div>
      \"\"\"

  Prefer:

      ~H\"\"\"
      <div class="progress" style={"--progress: \#{@percent}%"}></div>
      \"\"\"

  An inline style bypasses the design system's tokens: its sizes and colours
  are values no token names, and a stylesheet cannot change them. Give the
  element a named CSS class that uses tokens. A value that only the server
  knows, such as a percentage or an image address, reaches the stylesheet as a
  custom property, which the class reads with `var(--progress)`.

  A `style` attribute passes when every declaration in it starts with `--`.
  Static strings and string literals with interpolation are read; any other
  expression, such as `style={@style}`, cannot be proven to set only custom
  properties and is reported. Component calls are checked too, because a
  component usually passes `style` on to an element.

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
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoInlineStyle, []}
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
      HEEx templates should style elements with named CSS classes that use
      design-system tokens. An inline style may only set custom properties, which
      is how a value only the server knows reaches the stylesheet.
      """
    ]

  alias Bylaw.Credo.Heex

  @style_attr "style"
  @placeholder "\u0000"
  @message "Use a named CSS class that uses design-system tokens instead of an inline style. A style attribute may only set custom properties, such as style={\"--progress: \#{@percent}%\"}."

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.flat_map(&style_attrs/1)
    |> Enum.reject(&custom_properties_only?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp style_attrs(%Heex.Tag{attrs: attrs}), do: Enum.filter(attrs, &style_attr?/1)

  defp style_attr?(%{name: name}) when is_binary(name), do: String.downcase(name) == @style_attr
  defp style_attr?(_attr), do: false

  defp custom_properties_only?(%{value: value}) do
    case literal(value) do
      {:ok, text} -> declarations_are_custom_properties?(text)
      :error -> false
    end
  end

  defp literal({:string, value, _meta}) when is_binary(value), do: {:ok, value}

  defp literal({:expr, source, _meta}) when is_binary(source) do
    case Code.string_to_quoted(source) do
      {:ok, ast} -> literal_ast(ast)
      _error -> :error
    end
  end

  defp literal(_value), do: :error

  defp literal_ast(value) when is_binary(value), do: {:ok, value}

  defp literal_ast({:<<>>, _meta, parts}) do
    parts
    |> Enum.reduce_while({:ok, ""}, fn
      part, {:ok, text} when is_binary(part) -> {:cont, {:ok, text <> part}}
      {:"::", _, _}, {:ok, text} -> {:cont, {:ok, text <> @placeholder}}
      _part, _text -> {:halt, :error}
    end)
  end

  defp literal_ast(_ast), do: :error

  defp declarations_are_custom_properties?(text) do
    text
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.all?(&String.match?(&1, ~r/^--[\w-]+\s*:/))
  end

  defp issue_for(issue_meta, %{name: name, line: line, column: column}) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: name,
      line_no: line,
      column: column
    )
  end
end
