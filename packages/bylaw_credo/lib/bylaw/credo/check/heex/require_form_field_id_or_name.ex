defmodule Bylaw.Credo.Check.HEEx.RequireFormFieldIdOrName do
  @moduledoc """
  Requires static HEEx/HTML form controls to have an `id` or a `name`.

  ## Examples

  Avoid:

        ~H\"\"\"
        <input aria-label="Search">
        <textarea readonly aria-hidden="true" placeholder="Description"></textarea>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <input id="search" aria-label="Search">
        <p aria-hidden="true">Description</p>
        \"\"\"


  Browsers use a control's `id` or `name` to autofill it and to restore its
  value, and Chrome reports every control without either as a DevTools issue,
  again each time the page changes. A control with neither is also never
  submitted with its form. Give a real control a name, and render a decorative
  stand-in as a non-form element. Hidden, submit, button, reset and image inputs
  are not checked. Embedded `~H` templates are checked during normal Credo runs
  over Elixir files. Standalone `.html.heex` templates require enabling
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
          {Bylaw.Credo.Check.HEEx.RequireFormFieldIdOrName, []}
        ]
      }
    ]
  }
  ```

  ## Notes

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is available. Add `phoenix_live_view` to applications that enable this check.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:web],
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @control_tags ~w(input select textarea)
  @unchecked_input_types ~w(hidden submit button reset image)
  @message "Form controls must have an id or a name."
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tags/1)
    |> Enum.filter(&missing_id_and_name?/1)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp missing_id_and_name?(%Heex.Tag{type: :tag, name: name} = tag) when name in @control_tags do
    not Heex.has_attr?(tag, :root) and not unchecked_input?(tag) and
      not Heex.has_attr?(tag, "id") and not Heex.has_attr?(tag, "name")
  end

  defp missing_id_and_name?(_tag), do: false

  defp unchecked_input?(%Heex.Tag{name: "input", attrs: attrs}) do
    Enum.any?(attrs, &unchecked_type?/1)
  end

  defp unchecked_input?(_tag), do: false

  defp unchecked_type?(%{name: "type", value: {:string, value, _meta}}),
    do: String.downcase(value) in @unchecked_input_types

  defp unchecked_type?(%{name: "type", value: {:expr, _expr, _meta}}), do: true
  defp unchecked_type?(_attr), do: false

  defp issue_for(issue_meta, %Heex.Tag{} = tag) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: "<#{tag.name}",
      line_no: tag.line,
      column: tag.column
    )
  end
end
