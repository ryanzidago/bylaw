defmodule Bylaw.Credo.Check.HEEx.NoElementSpacing do
  @moduledoc """
  Discourages Tailwind margin utility classes on static HEEx/HTML elements.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  Dynamic class values, component tags, slot tags, and root attributes are
  ignored because their final DOM classes cannot be proven statically.
  Avoid:

        ~H\"\"\"
        <div class="mt-4">
          Content
        </div>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <div class="flex flex-col gap-4">
          <div>Content</div>
        </div>
        \"\"\"

  ## Notes

  Embedded `~H` templates in `.ex` and `.exs` files are checked by Credo's normal source traversal. Standalone `.html.heex` templates are checked when `Bylaw.Credo.Plugin.HEExSources` is enabled in `.credo.exs`.

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is available. Add `phoenix_live_view` to applications that enable this check.

  This check uses static HEEx token analysis, so it reports only patterns visible in the template source.

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
          {Bylaw.Credo.Check.HEEx.NoElementSpacing, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @message "Prefer parent-owned spacing with gap or space utilities instead of margin classes on individual elements."
  @margin_utilities ~w(m mx my ms me mt mr mb ml)
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.flat_map(&margin_class_attrs/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp margin_class_attrs(%Heex.Tag{type: :tag, attrs: attrs} = tag) do
    attrs
    |> Enum.filter(&static_class?/1)
    |> Enum.flat_map(&margin_tokens(tag, &1))
  end

  defp margin_class_attrs(_tag), do: []

  defp static_class?(%{name: name, value: {:string, value, _meta}})
       when is_binary(name) and is_binary(value) do
    String.downcase(name) == "class"
  end

  defp static_class?(_attr), do: false

  defp margin_tokens(tag, %{value: {:string, value, _meta}} = attr) do
    value
    |> class_tokens()
    |> Enum.filter(fn {token, _offset} -> margin_utility?(token) end)
    |> Enum.map(fn {token, offset} ->
      attr
      |> Map.put(:tag, tag)
      |> Map.put(:token, token)
      |> Map.put(:token_column, token_column(attr, offset))
    end)
  end

  defp class_tokens(value) do
    ~r/\S+/
    |> Regex.scan(value, return: :index)
    |> Enum.map(fn [{start, length}] -> {binary_part(value, start, length), start} end)
  end

  defp margin_utility?(token) do
    utility =
      token
      |> final_utility()
      |> strip_important_modifier()

    utility != "mx-auto" and
      Enum.any?(@margin_utilities, &String.starts_with?(utility, ["#{&1}-", "-#{&1}-"]))
  end

  defp final_utility(token) do
    token
    |> String.split(":")
    |> List.last()
  end

  defp strip_important_modifier("!" <> utility), do: utility
  defp strip_important_modifier(utility), do: utility

  defp token_column(%{name: name, column: column}, offset)
       when is_binary(name) and is_integer(column) do
    column + String.length(name) + 2 + offset
  end

  defp token_column(_attr, _offset), do: nil

  defp issue_for(issue_meta, %{tag: %Heex.Tag{} = tag, token: token, token_column: column} = attr) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: token,
      line_no: attr.line || tag.line,
      column: column || attr.column || tag.column
    )
  end
end
