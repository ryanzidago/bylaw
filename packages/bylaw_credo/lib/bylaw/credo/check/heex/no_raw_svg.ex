defmodule Bylaw.Credo.Check.HEEx.NoRawSVG do
  @moduledoc """
  Discourages raw SVG markup in HEEx templates.

  ## Examples

  Avoid:

      ~H\"\"\"
      <svg viewBox="0 0 16 16"><path d="M4 2.5v11l9-5.5z" /></svg>
      \"\"\"

  Prefer:

      ~H\"\"\"
      <.icon name="play" />
      \"\"\"

  Raw SVGs scattered through templates are hard to reuse and maintain. Use an
  SVG library or define custom SVGs in a separate component module. For the
  latter, exclude only that dedicated module's source file from this check
  using Credo's per-check `:files` option.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Options

  This check has no check-specific options. Use Credo's standard per-check
  `:files` option to exclude a dedicated SVG component module:

  ```elixir
  {Bylaw.Credo.Check.HEEx.NoRawSVG,
   [files: %{excluded: [~r{/components/custom_icons\\.ex$}]}]}
  ```

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.NoRawSVG, []}
        ]
      }
    ]
  }
  ```

  ## Notes

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is
  available. Add `phoenix_live_view` to applications that enable this check.
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    tags: [:web, :design_system],
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @message "Avoid raw SVGs. Define SVGs in a separate module or use an SVG library."

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.filter(&raw_svg?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp raw_svg?(%Heex.Tag{type: :tag, name: "svg"}), do: true
  defp raw_svg?(_tag), do: false

  defp issue_for(issue_meta, %Heex.Tag{} = tag) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "<svg",
      line_no: tag.line,
      column: tag.column
    )
  end
end
