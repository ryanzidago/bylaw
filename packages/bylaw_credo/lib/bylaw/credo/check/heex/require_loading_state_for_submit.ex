defmodule Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmit do
  @moduledoc """
  Requires HEEx submit forms and controls to expose a loading or disabled state.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.
  Avoid:

        ~H\"\"\"
        <.form for={@form} phx-submit="save">
          <button type="submit">Save</button>
        </.form>
        \"\"\"
  Prefer:

        ~H\"\"\"
        <.form for={@form} phx-submit="save">
          <button type="submit" phx-disable-with="Saving...">Save</button>
        </.form>
        \"\"\"

  Custom loading conventions can be configured with `:loading_attrs` or
  `:loading_class_patterns`.

  ## Notes

  Embedded `~H` templates in `.ex` and `.exs` files are checked by Credo's normal source traversal. Standalone `.html.heex` templates are checked when `Bylaw.Credo.Plugin.HEExSources` is enabled in `.credo.exs`.

  This check uses Phoenix LiveView's undocumented HEEx tokenizer when it is available. Add `phoenix_live_view` to applications that enable this check.

  This check uses static HEEx token analysis, so it reports only patterns visible in the template source.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmit,
           [
             loading_attrs: ["phx-disable-with", "disabled"],
             loading_class_patterns: ["is-loading"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:loading_attrs` - Attribute names that satisfy the loading-state requirement (default: phx-disable-with, disabled).
  - `:loading_class_patterns` - Class-name substrings that satisfy the loading-state requirement (default: none).

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.RequireLoadingStateForSubmit, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [
      loading_attrs: ["phx-disable-with", "disabled"],
      loading_class_patterns: []
    ],
    explanations: [
      check: @moduledoc,
      params: [
        loading_attrs:
          "Attribute names that satisfy the loading-state requirement (default: phx-disable-with, disabled).",
        loading_class_patterns:
          "Class-name substrings that satisfy the loading-state requirement (default: none)."
      ]
    ]

  alias Bylaw.Credo.Heex

  @message "Submit actions must expose a loading or disabled state."
  @form_tags [:tag, :local_component]
  @submit_control_tags ["button", "input"]
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    opts = %{
      loading_attrs: Params.get(params, :loading_attrs, __MODULE__),
      loading_class_patterns: Params.get(params, :loading_class_patterns, __MODULE__)
    }

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&Heex.tokens/1)
    |> submit_issues(opts)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp submit_issues(tokens, opts) do
    {issues, forms} =
      Enum.reduce(tokens, {[], []}, fn token, {issues, forms} ->
        case token do
          %Heex.Tag{closing: :self} = tag ->
            handle_self_closing_tag(tag, issues, forms, opts)

          %Heex.Tag{} = tag ->
            handle_open_tag(tag, issues, forms, opts)

          %Heex.CloseTag{name: "form"} ->
            close_form(issues, forms)

          _token ->
            {issues, forms}
        end
      end)

    issues
    |> close_remaining_forms(forms)
    |> Enum.reverse()
  end

  defp handle_self_closing_tag(tag, issues, forms, opts) do
    cond do
      submit_form?(tag) and not loading_state?(tag, opts) ->
        {[%{line: tag.line, column: tag.column, trigger: trigger_for(tag)} | issues], forms}

      submit_form?(tag) ->
        {issues, forms}

      submit_control?(tag) ->
        add_submit_control_issue(tag, issues, forms, opts)

      true ->
        {issues, forms}
    end
  end

  defp handle_open_tag(tag, issues, forms, opts) do
    cond do
      submit_form?(tag) ->
        form = %{
          line: tag.line,
          column: tag.column,
          trigger: trigger_for(tag),
          has_loading?: loading_state?(tag, opts),
          has_submit_control?: false
        }

        {issues, [form | forms]}

      submit_control?(tag) ->
        add_submit_control_issue(tag, issues, forms, opts)

      true ->
        {issues, forms}
    end
  end

  defp add_submit_control_issue(tag, issues, forms, opts) do
    has_loading? = loading_state?(tag, opts)
    forms = mark_current_form_submit_control(forms, has_loading?)

    issues =
      if has_loading? do
        issues
      else
        [%{line: tag.line, column: tag.column, trigger: trigger_for(tag)} | issues]
      end

    {issues, forms}
  end

  defp close_form(issues, [form | rest]) do
    if form.has_loading? or form.has_submit_control? do
      {issues, rest}
    else
      {[form | issues], rest}
    end
  end

  defp close_form(issues, []), do: {issues, []}

  defp close_remaining_forms(issues, forms) do
    Enum.reduce(forms, issues, fn form, issues ->
      elem(close_form(issues, [form]), 0)
    end)
  end

  defp mark_current_form_submit_control([form | rest], has_loading?) do
    [%{form | has_submit_control?: true, has_loading?: form.has_loading? or has_loading?} | rest]
  end

  defp mark_current_form_submit_control([], _has_loading?), do: []

  defp submit_form?(%Heex.Tag{type: type, name: "form"} = tag) when type in @form_tags do
    Heex.has_attr?(tag, "phx-submit") and not Heex.has_attr?(tag, :root)
  end

  defp submit_form?(_tag), do: false

  defp submit_control?(%Heex.Tag{type: :tag, name: name} = tag)
       when name in @submit_control_tags do
    static_attr_value?(tag, "type", "submit") and not Heex.has_attr?(tag, :root)
  end

  defp submit_control?(_tag), do: false

  defp loading_state?(%Heex.Tag{} = tag, opts) do
    loading_attr?(tag, opts.loading_attrs) or loading_class?(tag, opts.loading_class_patterns)
  end

  defp loading_attr?(tag, attr_names) do
    Enum.any?(attr_names, &Heex.has_attr?(tag, &1))
  end

  defp loading_class?(tag, patterns) do
    class =
      tag
      |> attr_value("class")
      |> static_string()

    is_binary(class) and Enum.any?(patterns, &String.contains?(class, &1))
  end

  defp static_attr_value?(tag, name, expected_value) do
    tag
    |> attr_value(name)
    |> static_string()
    |> case do
      ^expected_value -> true
      _value -> false
    end
  end

  defp attr_value(%Heex.Tag{attrs: attrs}, name) do
    case Enum.find(attrs, &(&1.name == name)) do
      nil -> nil
      attr -> attr.value
    end
  end

  defp static_string({:string, value, _meta}), do: value
  defp static_string(_value), do: nil

  defp trigger_for(%Heex.Tag{type: :local_component, name: name}), do: "<.#{name}"
  defp trigger_for(%Heex.Tag{name: name}), do: "<#{name}"

  defp issue_for(issue_meta, %{line: line, column: column, trigger: trigger}) do
    format_issue(
      issue_meta,
      message: @message,
      trigger: trigger,
      line_no: line,
      column: column
    )
  end
end
