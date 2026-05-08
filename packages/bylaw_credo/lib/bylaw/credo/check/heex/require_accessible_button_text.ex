defmodule Bylaw.Credo.Check.HEEx.RequireAccessibleButtonText do
  @moduledoc """
  Requires static HEEx/HTML button tags to have an accessible name.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  ## Bad

      ~H\"\"\"
      <button type="button"><.icon name="hero-x-mark" /></button>
      \"\"\"

  ## Good

      ~H\"\"\"
      <button type="button">Close</button>
      <button type="button" aria-label="Close"><.icon name="hero-x-mark" /></button>
      <button type="button">{@label}</button>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @message "Buttons must have text content, aria-label, or aria-labelledby."

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tokens/1)
    |> inaccessible_buttons()
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp inaccessible_buttons(tokens) do
    {issues, _stack} =
      Enum.reduce(tokens, {[], []}, fn token, {issues, stack} ->
        case token do
          %Heex.Tag{type: :tag, name: "button", closing: :self} = tag ->
            issues =
              if attrs_have_name?(tag) do
                issues
              else
                [%{line: tag.line, column: tag.column} | issues]
              end

            {issues, stack}

          %Heex.Tag{type: :tag, name: "button"} = tag ->
            button = %{
              line: tag.line,
              column: tag.column,
              has_name?: attrs_have_name?(tag)
            }

            {issues, [button | stack]}

          %Heex.Tag{closing: :self} ->
            {issues, stack}

          %Heex.CloseTag{name: "button"} ->
            close_button(issues, stack)

          %Heex.Text{content: content} ->
            {issues, mark_named(stack, text_name?(content))}

          %Heex.Expression{} ->
            {issues, mark_named(stack, true)}

          _token ->
            {issues, stack}
        end
      end)

    Enum.reverse(issues)
  end

  defp close_button(issues, [button | rest]) do
    if button.has_name? do
      {issues, rest}
    else
      {[button | issues], rest}
    end
  end

  defp close_button(issues, []), do: {issues, []}

  defp mark_named(stack, true), do: Enum.map(stack, &%{&1 | has_name?: true})
  defp mark_named(stack, false), do: stack

  defp text_name?(text) do
    text =
      text
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    text != ""
  end

  defp attrs_have_name?(%Heex.Tag{attrs: attrs}) do
    Enum.any?(attrs, fn attr ->
      attr.name == :root or
        (attr.name in ["aria-label", "aria-labelledby"] and non_empty_attr_value?(attr.value))
    end)
  end

  defp non_empty_attr_value?({:string, value, _meta}), do: String.trim(value) != ""
  defp non_empty_attr_value?(nil), do: false
  defp non_empty_attr_value?(_value), do: true

  defp issue_for(issue_meta, %{line: line, column: column}) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "<button",
      line_no: line,
      column: column
    )
  end
end
