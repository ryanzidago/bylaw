defmodule Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtmlPropertyTest do
  use Credo.Test.Case
  use ExUnitProperties

  alias Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtml

  property "two or more selector attributes always report regardless of order and spacing" do
    check all(
            attributes <- selector_attributes(2..5),
            element <- member_of(~w(button div input section span)),
            whitespace <- member_of([" ", "  ", "\n    "])
          ) do
      forward_source = assertion_source(element, attributes, whitespace)
      reversed_source = assertion_source(element, Enum.reverse(attributes), whitespace)

      forward_source
      |> to_source_file("test/forward_example_test.exs")
      |> run_check(PreferSelectorAssertionsForHtml)
      |> assert_issue()

      reversed_source
      |> to_source_file("test/reversed_example_test.exs")
      |> run_check(PreferSelectorAssertionsForHtml)
      |> assert_issue()
    end
  end

  property "zero or one selector attribute never reports" do
    check all(
            attributes <- one_of([constant([]), map(selector_attribute(), &[&1])]),
            element <- member_of(~w(button div input section span)),
            whitespace <- member_of([" ", "  ", "\n    "])
          ) do
      element
      |> assertion_source(attributes, whitespace)
      |> to_source_file("test/example_test.exs")
      |> run_check(PreferSelectorAssertionsForHtml)
      |> refute_issues()
    end
  end

  property "selector attributes on separate elements never combine into an issue" do
    check all(
            first_attribute <- selector_attribute(),
            second_attribute <- selector_attribute(),
            first_element <- member_of(~w(button div section span)),
            second_element <- member_of(~w(button div section span))
          ) do
      html =
        "<#{first_element} #{first_attribute}></#{first_element}>" <>
          "<#{second_element} #{second_attribute}></#{second_element}>"

      html
      |> source_with_assertion()
      |> to_source_file("test/example_test.exs")
      |> run_check(PreferSelectorAssertionsForHtml)
      |> refute_issues()
    end
  end

  defp selector_attribute do
    prefixed_attribute =
      gen all(
            prefix <- member_of(["phx-value-", "data-", "aria-"]),
            suffix <- identifier(),
            value <- identifier()
          ) do
        ~s(#{prefix}#{suffix}="#{value}")
      end

    one_of([
      constant(~s(id="generated")),
      constant(~s(class="generated")),
      prefixed_attribute
    ])
  end

  defp selector_attributes(count_range) do
    gen all(
          id_value <- identifier(),
          class_value <- identifier(),
          phx_value <- identifier(),
          data_value <- identifier(),
          aria_value <- identifier(),
          count <- integer(count_range),
          offset <- integer(0..4)
        ) do
      attributes = [
        ~s(id="#{id_value}"),
        ~s(class="#{class_value}"),
        ~s(phx-click="#{phx_value}"),
        ~s(data-role="#{data_value}"),
        ~s(aria-label="#{aria_value}")
      ]

      {before_offset, after_offset} = Enum.split(attributes, offset)

      after_offset
      |> Kernel.++(before_offset)
      |> Enum.take(count)
    end
  end

  defp identifier do
    gen all(characters <- list_of(member_of(Enum.to_list(?a..?z)), min_length: 1, max_length: 10)) do
      List.to_string(characters)
    end
  end

  defp assertion_source(element, attributes, whitespace) do
    opening_tag =
      "<#{element}#{whitespace}#{Enum.join(attributes, whitespace)} title=\"generated\">"

    source_with_assertion(opening_tag <> "content</#{element}>")
  end

  defp source_with_assertion(html) do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders markup" do
        assert html =~ ~S(#{html})
      end
    end
    """
  end
end
