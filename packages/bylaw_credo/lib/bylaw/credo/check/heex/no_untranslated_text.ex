defmodule Bylaw.Credo.Check.HEEx.NoUntranslatedText do
  @moduledoc """
  Forbid literal, readable text in HEEx templates so every word a person can read comes from an expression, usually `gettext/1`.

  ## Examples

  Avoid:

        ~H\"\"\"
        <h1>Your order</h1>
        <input type="email" name="email" placeholder="Your email" />
        <button type="submit" phx-disable-with="Saving…">Save</button>
        \"\"\"

  Prefer:

        ~H\"\"\"
        <h1>{gettext("Your order")}</h1>
        <input type="email" name="email" placeholder={gettext("Your email")} />
        <button type="submit" phx-disable-with={gettext("Saving…")}>{gettext("Save")}</button>
        \"\"\"


  Text written straight into a template is shown in one language to every
  visitor, and nothing fails when a translator never sees it. Routing it
  through gettext puts it in the extracted `.pot` files, where missing
  translations are visible. Brand names are not exempt: they go through
  gettext too, and their translation is simply the same word.

  The check reads `~H` sigils and `.html.heex` templates and reports:

  - a text node that contains a letter from any script (`\\p{L}`);
  - a letter in the literal value of a user-visible attribute (see
    `:visible_attributes`);
  - a letter in the literal `value` of an `<input>` whose type is `submit`,
    `button` or `reset`, which the browser shows as the button's text. A
    `<button>`'s `value` is sent with the form and never shown, so it is not
    checked.

  It allows text made only of punctuation, digits, whitespace and symbols
  (`€`, `%`, `·`, `×`, `→`), HTML entities such as `&nbsp;`, the doctype, HTML
  and HEEx comments, the bodies of `<script>` and `<style>`, and every other
  attribute, such as `class`, `id`, `href`, `name` or `data-*`.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.NoUntranslatedText,
           [
             visible_attributes: ~w(alt title placeholder aria-label label),
             files: %{excluded: [~r"lib/my_app_web/components/"]}
           ]}
        ]
      }
    ]
  }
  ```

  - `:visible_attributes` - Attribute names whose literal values people read.
    Defaults to `alt`, `title`, `placeholder`, `aria-label`,
    `aria-description`, `label` and `phx-disable-with` (the text a button
    shows while its event runs).

  Use Credo's per-check `files: %{excluded: [...]}` option to skip templates
  that are not translated yet.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.NoUntranslatedText, []}
        ]
      }
    ]
  }
  ```

  ## Notes

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is
  available. Add `phoenix_live_view` to applications that enable this check.
  Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:web],
    param_defaults: [
      visible_attributes:
        ~w(alt title placeholder aria-label aria-description label phx-disable-with)
    ],
    explanations: [
      check: @moduledoc,
      params: [
        visible_attributes: "Attribute names whose literal values people read."
      ]
    ]

  alias Bylaw.Credo.Heex

  @letter ~r/\p{L}/u
  @entity ~r/&(#[0-9]+|#x[0-9a-fA-F]+|[a-zA-Z][a-zA-Z0-9]*);/
  @not_text ~r/<!--.*?-->|<!doctype[^>]*>/is
  @button_input_types ~w(submit button reset)
  @raw_text_tags ~w(script style)
  @message ~S|Translate this text: render it from an expression such as {gettext("…")}.|

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    visible_attributes = Params.get(params, :visible_attributes, __MODULE__)

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&findings(&1, visible_attributes))
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp findings(template, visible_attributes) do
    template
    |> Heex.tokens()
    |> Enum.reduce({[], nil}, &visit(&1, &2, visible_attributes))
    |> elem(0)
    |> Enum.reverse()
  end

  defp visit(%Heex.Tag{type: :tag, name: name, closing: nil}, {found, nil}, _visible)
       when name in @raw_text_tags do
    {found, name}
  end

  defp visit(%Heex.CloseTag{name: name}, {found, name}, _visible), do: {found, nil}

  defp visit(_token, {found, raw_tag}, _visible) when is_binary(raw_tag), do: {found, raw_tag}

  defp visit(%Heex.Text{} = text, {found, nil}, _visible) do
    {text_findings(text) ++ found, nil}
  end

  defp visit(%Heex.Tag{} = tag, {found, nil}, visible) do
    findings =
      tag
      |> attribute_findings(visible)
      |> Enum.reverse()

    {findings ++ found, nil}
  end

  defp visit(_token, acc, _visible), do: acc

  defp text_findings(%Heex.Text{content: content, line_end: line_end}) do
    without_comments =
      Regex.replace(@not_text, content, &String.duplicate("\n", count_newlines(&1)))

    readable = Regex.replace(@entity, without_comments, " ")

    case Regex.run(@letter, readable, return: :index) do
      [{offset, _length}] ->
        rest = binary_part(readable, offset, byte_size(readable) - offset)
        [{(line_end || 1) - count_newlines(rest), squish(readable)}]

      nil ->
        []
    end
  end

  defp attribute_findings(%Heex.Tag{} = tag, visible) do
    tag.attrs
    |> Enum.filter(&visible_attribute?(&1, tag, visible))
    |> Enum.flat_map(fn %{name: name, value: {:string, value, _value_meta}} = attr ->
      if readable_text?(value) do
        [{attr.line || tag.line, "#{name}=\"#{squish(value)}\""}]
      else
        []
      end
    end)
  end

  defp visible_attribute?(%{name: name, value: {:string, _value, _meta}}, tag, visible)
       when is_binary(name) do
    name in visible or (name == "value" and button_input?(tag))
  end

  defp visible_attribute?(_attr, _tag, _visible), do: false

  defp button_input?(%Heex.Tag{type: :tag, name: "input", attrs: attrs}) do
    Enum.any?(attrs, fn attr ->
      match?(
        %{name: "type", value: {:string, type, _meta}} when type in @button_input_types,
        attr
      )
    end)
  end

  defp button_input?(_tag), do: false

  defp readable_text?(value) do
    Regex.match?(@letter, Regex.replace(@entity, value, " "))
  end

  defp count_newlines(text) do
    text
    |> String.split("\n")
    |> Enum.count()
    |> Kernel.-(1)
  end

  defp squish(text) do
    text
    |> String.split()
    |> Enum.join(" ")
  end

  defp issue_for(issue_meta, {line_no, text}) do
    format_issue(issue_meta, message: @message, trigger: text, line_no: line_no)
  end
end
