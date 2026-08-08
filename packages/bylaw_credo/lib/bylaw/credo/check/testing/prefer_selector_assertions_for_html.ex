defmodule Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtml do
  @moduledoc """
  Prefer selector-based assertions over comparisons against serialized HTML
  with multiple selector-relevant attributes.

  ## Examples

  Avoid:

      assert html =~ ~s(<button id="save" phx-click="save">Save</button>)

  Prefer:

      assert has_element?(view, "#save[phx-click=save]")

  ## Notes

  HTML attribute order has no semantic meaning, and serializers may emit the
  same attributes in a different order. Comparing serialized HTML can therefore
  produce flaky tests even when the DOM is unchanged. Selector-based assertions
  express the intended DOM contract without coupling tests to serialization
  details.

  The check reports direct `assert` and `refute` comparisons using `==`, `===`,
  `!=`, `!==`, or `=~` when a string operand contains an opening HTML tag with
  at least two `phx-*`, `data-*`, `aria-*`, `id`, or `class` attributes.

  Path exclusions are matched against the source filename and are intended for
  snapshots or tests where exact serialization is deliberately the contract.

  The check uses static AST analysis, so dynamically constructed strings and
  macro-expanded assertions may fall outside its signal.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtml,
           [excluded_paths: ["test/snapshots/"]]}
        ]
      }
    ]
  }
  ```

  - `:excluded_paths` - Paths containing any configured string are skipped.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :refactor,
    tags: [:testing, :web, :accessibility],
    param_defaults: [excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: """
        Paths containing any configured string are skipped. Use this for
        snapshots or tests that intentionally verify exact serialization.
        """
      ]
    ]

  @comparison_operators [:==, :===, :!=, :!==, :=~]
  @selector_attribute ~r/(?:^|\s)(?:phx-[\w:-]+|data-[\w:-]+|aria-[\w:-]+|id|class)\s*=/i

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if test_file?(source_file.filename) and not excluded?(source_file.filename, excluded_paths) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_file?(filename), do: String.ends_with?(filename, "_test.exs")

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &String.contains?(filename, &1))
  end

  defp traverse({assertion, meta, [comparison | _rest]} = ast, issues, issue_meta)
       when assertion in [:assert, :refute] do
    if brittle_html_comparison?(comparison) do
      issue =
        format_issue(
          issue_meta,
          message:
            "Prefer a selector-based assertion; serialized HTML attribute order is not stable.",
          trigger: Atom.to_string(assertion),
          line_no: meta[:line] || 0
        )

      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp brittle_html_comparison?({operator, _meta, [left, right]})
       when operator in @comparison_operators do
    brittle_html_literal?(left) or brittle_html_literal?(right)
  end

  defp brittle_html_comparison?(_ast), do: false

  defp brittle_html_literal?(value) when is_binary(value) do
    value
    |> opening_tags_without_quoted_values()
    |> Enum.any?(fn tag ->
      @selector_attribute
      |> Regex.scan(tag)
      |> Enum.count()
      |> Kernel.>=(2)
    end)
  end

  defp brittle_html_literal?({sigil, _meta, [{:<<>>, _string_meta, parts}, modifiers]})
       when sigil in [:sigil_s, :sigil_S] and modifiers == [] do
    if Enum.all?(parts, &is_binary/1) do
      parts
      |> Enum.join()
      |> brittle_html_literal?()
    else
      false
    end
  end

  defp brittle_html_literal?(_ast), do: false

  defp opening_tags_without_quoted_values(html) do
    collect_opening_tags(html, [])
  end

  defp collect_opening_tags(<<>>, tags), do: Enum.reverse(tags)

  defp collect_opening_tags(<<"<", first, rest::binary>>, tags)
       when first in ?A..?Z or first in ?a..?z do
    case consume_opening_tag(rest, <<"<", first>>, nil) do
      {:ok, tag, remaining_html} -> collect_opening_tags(remaining_html, [tag | tags])
      :error -> Enum.reverse(tags)
    end
  end

  defp collect_opening_tags(<<_character, rest::binary>>, tags) do
    collect_opening_tags(rest, tags)
  end

  defp consume_opening_tag(<<>>, _tag, _quote), do: :error

  defp consume_opening_tag(<<character, rest::binary>>, tag, quote)
       when character == quote do
    consume_opening_tag(rest, tag, nil)
  end

  defp consume_opening_tag(<<character, rest::binary>>, tag, nil)
       when character in [?", ?'] do
    empty_quoted_value = <<character, character>>
    consume_opening_tag(rest, tag <> empty_quoted_value, character)
  end

  defp consume_opening_tag(<<">", rest::binary>>, tag, nil) do
    {:ok, tag <> ">", rest}
  end

  defp consume_opening_tag(<<_character, rest::binary>>, tag, quote)
       when quote in [?", ?'] do
    consume_opening_tag(rest, tag, quote)
  end

  defp consume_opening_tag(<<character, rest::binary>>, tag, nil) do
    consume_opening_tag(rest, tag <> <<character>>, nil)
  end
end
