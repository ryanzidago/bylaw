defmodule Bylaw.Credo.Check.HEEx.PreferComponentModule do
  @moduledoc """
  Prefers configured component modules for matching HEEx UI patterns.

  ## Examples

  Embedded `~H` templates are checked during normal Credo runs over Elixir
  files. Standalone `.html.heex` templates require enabling
  `Bylaw.Credo.Plugin.HEExSources` in Credo's `plugins` configuration.

  Configure explicit rules for the UI patterns your application wants to route
  through shared component modules:

        {Bylaw.Credo.Check.HEEx.PreferComponentModule,
         rules: [
           [
             prefer: MyAppWeb.UI.Buttons,
             when: [[html_tag: "button"]]
           ],
           [
             prefer: MyAppWeb.UI.Tables,
             when: [[html_tag: "table"]]
           ],
           [
             prefer: MyAppWeb.UI.Cards,
             when: [[attrs: [class: ~r/\\bcard\\b/]]]
           ]
         ]}

  Avoid:

        ~H\"\"\"
        <button type="button">Save</button>
        \"\"\"

  Prefer calling a component from the configured module:

        ~H\"\"\"
        <Buttons.button type="button">Save</Buttons.button>
        \"\"\"

  ## Notes

  This check does not register or discover component functions. The configured
  `:prefer` module is the policy target, and callers decide which function from
  that module should replace the flagged markup.

  Matchers in a rule's `:when` list are ORed. Keys inside one matcher are ANDed.

  This check uses static HEEx token analysis, so it reports only patterns
  visible in the template source.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.PreferComponentModule,
           rules: [
             [prefer: MyAppWeb.UI.Buttons, when: [[html_tag: "button"]]],
             [prefer: MyAppWeb.UI.Tables, when: [[html_tag: "table"]]],
             [
               prefer: MyAppWeb.UI.Dropdowns,
               when: [
                 [attrs: [role: "menu"]],
                 [attrs: ["aria-haspopup": "menu"]]
               ]
             ]
           ]}
        ]
      }
    ]
  }
  ```

  - `:rules` - Non-empty list of rules. Each rule requires `:prefer` and `:when`.
  - `:prefer` - Component module that should own matching UI.
  - `:when` - Non-empty list of matchers.

  Supported matcher keys:

  - `:html_tag` - Static HEEx/HTML tag name, such as `"button"` or `"table"`.
  - `:attrs` - Attribute predicates, such as `[role: "menu"]`,
    `[phx_click: :present]`, or `[class: ~r/\\bcard\\b/]`.
  - `:css_selector` - Simple tag/class selector, such as `"div.card"`.
  - `:regex` - Regex matched against the template source.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [rules: []],
    explanations: [
      check: @moduledoc,
      params: [
        rules: "Rules that map matching HEEx UI patterns to a preferred component module."
      ]
    ]

  alias Bylaw.Credo.Heex

  @allowed_rule_keys [:prefer, :when]
  @allowed_matcher_keys [:html_tag, :attrs, :css_selector, :regex]
  @present :present

  @doc false
  @impl Credo.Check
  @spec run(Credo.SourceFile.t(), Keyword.t()) :: list(Credo.Issue.t())
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    rules = normalize_rules!(Params.get(params, :rules, __MODULE__))

    source_file
    |> Heex.templates()
    |> Enum.flat_map(&issues_for_template(&1, rules))
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp issues_for_template(%Heex.Template{} = template, rules) do
    tag_issues =
      template
      |> Heex.tags()
      |> Enum.filter(&match?(%Heex.Tag{type: :tag}, &1))
      |> Enum.flat_map(&issues_for_tag(&1, template, rules))

    regex_issues = Enum.flat_map(rules, &regex_issues_for_rule(&1, template))

    tag_issues ++ regex_issues
  end

  defp issues_for_tag(%Heex.Tag{} = tag, %Heex.Template{} = template, rules) do
    rules
    |> Enum.filter(&tag_rule_match?(&1, tag, template.source))
    |> Enum.map(&tag_issue(tag, &1))
  end

  defp tag_rule_match?(rule, %Heex.Tag{} = tag, source) do
    Enum.any?(rule.matchers, &tag_matcher_match?(&1, tag, source))
  end

  defp tag_matcher_match?(matcher, %Heex.Tag{} = tag, source) do
    not regex_only_matcher?(matcher) and
      Enum.all?(matcher, &tag_matcher_key_match?(&1, tag, source))
  end

  defp tag_matcher_key_match?({:html_tag, expected}, %Heex.Tag{name: name}, _source),
    do: name == expected

  defp tag_matcher_key_match?({:attrs, expected_attrs}, %Heex.Tag{} = tag, _source) do
    Enum.all?(expected_attrs, &attr_match?(&1, tag))
  end

  defp tag_matcher_key_match?({:css_selector, selector}, %Heex.Tag{} = tag, _source) do
    selector_match?(selector, tag)
  end

  defp tag_matcher_key_match?({:regex, regex}, _tag, source), do: Regex.match?(regex, source)

  defp regex_issues_for_rule(rule, %Heex.Template{} = template) do
    rule.matchers
    |> Enum.filter(&regex_only_matcher?/1)
    |> Enum.flat_map(fn matcher ->
      matcher
      |> Keyword.fetch!(:regex)
      |> regex_issues(template, rule)
    end)
  end

  defp regex_only_matcher?(matcher), do: Keyword.keys(matcher) == [:regex]

  defp regex_issues(%Regex{} = regex, %Heex.Template{} = template, rule) do
    regex
    |> Regex.scan(template.source, return: :index)
    |> Enum.map(fn [{start, length} | _captures] ->
      {line, column} = position_for_index(template, start)

      %{
        prefer: rule.prefer,
        line: line,
        column: column,
        trigger: binary_part(template.source, start, length)
      }
    end)
  end

  defp attr_match?({name, expected_value}, %Heex.Tag{attrs: attrs}) do
    name = attr_name(name)

    case Enum.find(attrs, &(&1.name == name)) do
      nil -> false
      attr -> attr_value_match?(attr.value, expected_value)
    end
  end

  defp attr_value_match?(_actual, @present), do: true

  defp attr_value_match?(actual, %Regex{} = regex) do
    case attr_value_string(actual) do
      {:ok, value} -> Regex.match?(regex, value)
      :error -> false
    end
  end

  defp attr_value_match?(actual, expected) when is_binary(expected) do
    case attr_value_string(actual) do
      {:ok, ^expected} -> true
      _other -> false
    end
  end

  defp attr_value_match?(_actual, _expected), do: false

  defp attr_value_string({:string, value, _meta}) when is_binary(value), do: {:ok, value}
  defp attr_value_string({:expr, value, _meta}) when is_binary(value), do: {:ok, value}
  defp attr_value_string(value) when is_binary(value), do: {:ok, value}
  defp attr_value_string(_value), do: :error

  defp selector_match?(selector, %Heex.Tag{} = tag) do
    case parse_simple_selector(selector) do
      {:ok, %{tag: selector_tag, class: class}} ->
        selector_tag_match?(tag, selector_tag) and selector_class_match?(tag, class)

      :error ->
        false
    end
  end

  defp parse_simple_selector(selector) when is_binary(selector) do
    case Regex.run(~r/\A(?<tag>[a-z][a-z0-9-]*)?(?:\.(?<class>[A-Za-z0-9_-]+))?\z/, selector,
           capture: :all_names
         ) do
      [class, tag] when tag != "" or class != "" ->
        {:ok, %{tag: empty_to_nil(tag), class: empty_to_nil(class)}}

      _no_match ->
        :error
    end
  end

  defp parse_simple_selector(_selector), do: :error

  defp selector_tag_match?(_tag, nil), do: true
  defp selector_tag_match?(%Heex.Tag{name: name}, selector_tag), do: name == selector_tag

  defp selector_class_match?(_tag, nil), do: true

  defp selector_class_match?(%Heex.Tag{} = tag, class) do
    attr_match?({"class", ~r/(?:^|\s)#{Regex.escape(class)}(?:\s|$)/}, tag)
  end

  defp position_for_index(%Heex.Template{} = template, index) do
    before_match = binary_part(template.source, 0, index)
    lines = String.split(before_match, "\n")
    line_offset = Enum.count(lines) - 1
    last_line = List.last(lines)

    column =
      if line_offset == 0 do
        template.column + String.length(last_line)
      else
        String.length(last_line) + 1
      end

    {template.line + line_offset, column}
  end

  defp tag_issue(%Heex.Tag{} = tag, rule) do
    %{
      prefer: rule.prefer,
      line: tag.line,
      column: tag.column,
      trigger: "<#{tag.name}"
    }
  end

  defp issue_for(issue_meta, issue) do
    format_issue(
      issue_meta,
      message:
        "Use #{inspect(issue.prefer)} for this UI pattern instead of raw or local HEEx markup.",
      trigger: issue.trigger,
      line_no: issue.line,
      column: issue.column
    )
  end

  defp normalize_rules!(rules) when is_list(rules) do
    if Enum.empty?(rules) do
      raise ArgumentError, "expected #{__MODULE__} :rules to be a non-empty list of rules"
    end

    Enum.map(rules, &normalize_rule!/1)
  end

  defp normalize_rules!(rules) do
    raise ArgumentError,
          "expected #{__MODULE__} :rules to be a non-empty list of rules, got: #{inspect(rules)}"
  end

  defp normalize_rule!(rule) when is_list(rule) do
    if Keyword.keyword?(rule) do
      validate_allowed_keys!(rule, @allowed_rule_keys, "rule")

      %{
        prefer: prefer!(rule),
        matchers: matchers!(rule)
      }
    else
      raise_rule_error!(rule)
    end
  end

  defp normalize_rule!(rule), do: raise_rule_error!(rule)

  defp prefer!(rule) do
    case Keyword.fetch(rule, :prefer) do
      {:ok, prefer} when is_atom(prefer) and prefer not in [nil, false, true] ->
        prefer

      {:ok, prefer} ->
        raise ArgumentError,
              "expected #{__MODULE__} rule :prefer to be a module, got: #{inspect(prefer)}"

      :error ->
        raise ArgumentError, "missing required #{__MODULE__} rule option: :prefer"
    end
  end

  defp matchers!(rule) do
    case Keyword.fetch(rule, :when) do
      {:ok, matchers} -> normalize_matchers!(matchers)
      :error -> raise ArgumentError, "missing required #{__MODULE__} rule option: :when"
    end
  end

  defp normalize_matchers!(matchers) when is_list(matchers) do
    cond do
      Enum.empty?(matchers) ->
        raise_matchers_error!(matchers)

      Enum.all?(matchers, &Keyword.keyword?/1) ->
        Enum.map(matchers, &normalize_matcher!/1)

      true ->
        raise_matchers_error!(matchers)
    end
  end

  defp normalize_matchers!(matchers), do: raise_matchers_error!(matchers)

  defp normalize_matcher!(matcher) do
    validate_allowed_keys!(matcher, @allowed_matcher_keys, "matcher")

    if Enum.empty?(matcher) do
      raise_matchers_error!(matcher)
    end

    Enum.map(matcher, &normalize_matcher_option!/1)
  end

  defp normalize_matcher_option!({:html_tag, value}) when is_binary(value) and value != "" do
    {:html_tag, value}
  end

  defp normalize_matcher_option!({:html_tag, value}) do
    raise ArgumentError,
          "expected #{__MODULE__} matcher :html_tag to be a non-empty string, got: #{inspect(value)}"
  end

  defp normalize_matcher_option!({:attrs, attrs}) when is_list(attrs) do
    if Keyword.keyword?(attrs) and not Enum.empty?(attrs) do
      {:attrs, Enum.map(attrs, &normalize_attr_option!/1)}
    else
      raise_attrs_error!(attrs)
    end
  end

  defp normalize_matcher_option!({:attrs, attrs}), do: raise_attrs_error!(attrs)

  defp normalize_matcher_option!({:css_selector, selector})
       when is_binary(selector) and selector != "" do
    {:css_selector, selector}
  end

  defp normalize_matcher_option!({:css_selector, selector}) do
    raise ArgumentError,
          "expected #{__MODULE__} matcher :css_selector to be a non-empty string, got: #{inspect(selector)}"
  end

  defp normalize_matcher_option!({:regex, %Regex{} = regex}), do: {:regex, regex}

  defp normalize_matcher_option!({:regex, regex}) do
    raise ArgumentError,
          "expected #{__MODULE__} matcher :regex to be a Regex, got: #{inspect(regex)}"
  end

  defp normalize_attr_option!({name, value}) do
    name = attr_name(name)

    if valid_attr_value?(value) do
      {name, value}
    else
      raise ArgumentError,
            "expected #{__MODULE__} matcher :attrs values to be strings, regexes, or :present, got: #{inspect(value)}"
    end
  end

  defp attr_name(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp attr_name(name) when is_binary(name), do: name

  defp attr_name(name) do
    raise ArgumentError,
          "expected #{__MODULE__} matcher :attrs keys to be strings or atoms, got: #{inspect(name)}"
  end

  defp valid_attr_value?(@present), do: true
  defp valid_attr_value?(value) when is_binary(value), do: true
  defp valid_attr_value?(%Regex{}), do: true
  defp valid_attr_value?(_value), do: false

  defp validate_allowed_keys!(opts, allowed_keys, label) do
    Enum.each(opts, fn {key, _value} ->
      if key not in allowed_keys do
        raise ArgumentError, "unknown #{__MODULE__} #{label} option: #{inspect(key)}"
      end
    end)
  end

  defp raise_rule_error!(rule) do
    raise ArgumentError,
          "expected #{__MODULE__} rule to be a keyword list, got: #{inspect(rule)}"
  end

  defp raise_matchers_error!(matchers) do
    raise ArgumentError,
          "expected #{__MODULE__} rule :when to be a non-empty list of matchers, got: #{inspect(matchers)}"
  end

  defp raise_attrs_error!(attrs) do
    raise ArgumentError,
          "expected #{__MODULE__} matcher :attrs to be a non-empty keyword list, got: #{inspect(attrs)}"
  end

  defp empty_to_nil(""), do: nil
  defp empty_to_nil(value), do: value
end
