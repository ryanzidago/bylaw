defmodule Bylaw.Credo.Check.HEEx.RequireTargetBlankRel do
  @moduledoc """
  Requires static HEEx/HTML links with `target="_blank"` to define safe `rel`.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  Avoid:

        ~H\"\"\"
        <a href="https://example.com" target="_blank">Example</a>
        <a href="https://example.com" target="_blank" rel="external">Example</a>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <a href="https://example.com" target="_blank" rel="noopener">Example</a>
        <a href="https://example.com" target="_blank" rel="external noopener noreferrer">Example</a>
        <a href="https://example.com" target={@target} rel={@rel}>Example</a>
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
          {Bylaw.Credo.Check.HEEx.RequireTargetBlankRel, []}
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

  @message ~s(Links with target="_blank" must define rel with noopener.)
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.filter(&unsafe_target_blank?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp unsafe_target_blank?(%Heex.Tag{type: :tag, name: "a"} = tag) do
    static_target_blank?(tag) and not dynamic_attrs?(tag) and not safe_rel?(tag)
  end

  defp unsafe_target_blank?(_tag), do: false

  defp static_target_blank?(%Heex.Tag{} = tag) do
    case attr_value(tag, "target") do
      {:string, target, _meta} -> String.downcase(target) == "_blank"
      _other -> false
    end
  end

  defp dynamic_attrs?(%Heex.Tag{} = tag), do: Heex.has_attr?(tag, :root)

  defp safe_rel?(%Heex.Tag{} = tag) do
    case attr_value(tag, "rel") do
      {:string, rel, _meta} -> rel_has_token?(rel, "noopener")
      {:expr, _expr, _meta} -> true
      _other -> false
    end
  end

  defp rel_has_token?(rel, token) do
    rel
    |> String.split()
    |> Enum.any?(&(String.downcase(&1) == token))
  end

  defp attr_value(%Heex.Tag{attrs: attrs}, name) do
    case Enum.find(attrs, &(&1.name == name)) do
      %{value: value} -> value
      nil -> nil
    end
  end

  defp issue_for(issue_meta, %Heex.Tag{} = tag) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "<a",
      line_no: tag.line,
      column: tag.column
    )
  end
end
