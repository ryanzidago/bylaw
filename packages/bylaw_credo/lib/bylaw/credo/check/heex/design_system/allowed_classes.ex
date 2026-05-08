defmodule Bylaw.Credo.Check.HEEx.DesignSystem.AllowedClasses do
  @moduledoc """
  Enforces configured design-system class scales in static HEEx `class` attributes.

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  This check intentionally only inspects static class strings. Dynamic-only
  values such as `class={@class}` are ignored.

  ## Configuration

      {Bylaw.Credo.Check.HEEx.DesignSystem.AllowedClasses,
       rules: [
         [prefix: "duration-", allowed: ~w(duration-150)],
         [prefix: "rounded-", allowed: ~w(rounded-none rounded-sm rounded rounded-md)]
       ]}

  ## Bad

      ~H\"\"\"
      <div class="duration-300 rounded-lg"></div>
      \"\"\"

  ## Good

      ~H\"\"\"
      <div class="duration-150 rounded-md"></div>
      <div class={@class}></div>
      \"\"\"
  """

  use Credo.Check,
    base_priority: :normal,
    category: :warning,
    param_defaults: [rules: []],
    explanations: [
      check: """
      Static HEEx class attributes should use the project-defined design-system
      scales for configured prefixes. Classes outside configured prefixes are
      ignored.
      """,
      params: [
        rules:
          "Keyword lists with :prefix and :allowed keys, defining the allowed class values for each prefix."
      ]
    ]

  alias Bylaw.Credo.Heex

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    rules = normalize_rules(Params.get(params, :rules, __MODULE__))

    if Enum.empty?(rules) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Heex.templates()
      |> Enum.flat_map(&Heex.tags/1)
      |> Enum.flat_map(&static_class_values/1)
      |> Enum.flat_map(&violations_for(&1, rules))
      |> Enum.map(&issue_for(issue_meta, &1))
    end
  end

  defp normalize_rules(rules) when is_list(rules) do
    rules
    |> Enum.flat_map(&normalize_rule/1)
  end

  defp normalize_rules(_rules), do: []

  defp normalize_rule(rule) when is_list(rule) do
    prefix = Keyword.get(rule, :prefix)
    allowed = Keyword.get(rule, :allowed, [])

    if is_binary(prefix) and is_list(allowed) and Enum.all?(allowed, &is_binary/1) do
      [%{prefix: prefix, allowed: allowed}]
    else
      []
    end
  end

  defp normalize_rule(_rule), do: []

  defp static_class_values(%Heex.Tag{type: type, attrs: attrs})
       when type in [:tag, :local_component, :remote_component] do
    Enum.flat_map(attrs, &static_class_attr_values/1)
  end

  defp static_class_values(_tag), do: []

  defp static_class_attr_values(%{name: "class", value: {:string, value, _meta}} = attr)
       when is_binary(value) do
    value
    |> class_tokens()
    |> Enum.map(fn {class, offset} ->
      %{class: class, line: attr.line, column: literal_class_column(attr, offset)}
    end)
  end

  defp static_class_attr_values(%{name: "class", value: {:expr, expression, meta}} = attr)
       when is_binary(expression) do
    expression
    |> static_expression_class_strings()
    |> Enum.flat_map(&class_tokens/1)
    |> Enum.map(fn {class, _offset} ->
      %{class: class, line: attr.line, column: expression_class_column(expression, meta, class)}
    end)
  end

  defp static_class_attr_values(_attr), do: []

  defp static_expression_class_strings(expression) do
    with {:ok, ast} <- Code.string_to_quoted(expression, columns: true, token_metadata: true) do
      collect_static_class_strings(ast)
    else
      _error -> []
    end
  end

  defp collect_static_class_strings(value) when is_binary(value), do: [value]

  defp collect_static_class_strings(values) when is_list(values) do
    Enum.flat_map(values, &collect_static_class_strings/1)
  end

  defp collect_static_class_strings({:sigil_w, _meta, [{:<<>>, _text_meta, [value]}, _modifiers]})
       when is_binary(value) do
    [value]
  end

  defp collect_static_class_strings({form, _meta, args})
       when form in [:&&, :||] and is_list(args) do
    Enum.flat_map(args, &collect_static_class_strings/1)
  end

  defp collect_static_class_strings({:if, _meta, [_condition, clauses]}) when is_list(clauses) do
    clauses
    |> Keyword.values()
    |> Enum.flat_map(&collect_static_class_strings/1)
  end

  defp collect_static_class_strings(_ast), do: []

  defp violations_for(%{class: class} = class_value, rules) do
    class_violations(class, class_value, rules)
  end

  defp class_tokens(value) do
    ~r/\S+/
    |> Regex.scan(value, return: :index)
    |> Enum.map(fn [{offset, length}] -> {String.slice(value, offset, length), offset} end)
  end

  defp class_violations(class, class_value, rules) do
    rules
    |> Enum.filter(&String.starts_with?(class, &1.prefix))
    |> Enum.reject(&(class in &1.allowed))
    |> Enum.map(&Map.merge(&1, class_value))
  end

  defp issue_for(issue_meta, %{
         class: class,
         prefix: prefix,
         allowed: allowed,
         line: line,
         column: column
       }) do
    format_issue(
      issue_meta,
      message:
        ~s(Class "#{class}" is outside the configured "#{prefix}" design-system scale. ) <>
          "Allowed: #{Enum.join(allowed, ", ")}.",
      trigger: class,
      line_no: line,
      column: column
    )
  end

  defp literal_class_column(%{column: column}, offset) when is_integer(column) do
    column + String.length(~s(class=")) + offset
  end

  defp literal_class_column(_attr, _offset), do: nil

  defp expression_class_column(expression, %{column: column}, class) when is_integer(column) do
    case :binary.match(expression, class) do
      {offset, _length} -> column + offset
      :nomatch -> column
    end
  end

  defp expression_class_column(_expression, _meta, _class), do: nil
end
