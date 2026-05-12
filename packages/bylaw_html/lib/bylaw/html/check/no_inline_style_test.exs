defmodule Bylaw.HTML.Check.NoInlineStyleTest do
  use ExUnit.Case, async: true

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.NoInlineStyle
  alias Bylaw.HTML.Issue

  describe "validate_html/2 with NoInlineStyle" do
    test "passes elements without inline style attributes" do
      html = ~s(<div class="hidden"><button class="button">Save</button></div>)

      assert :ok = HTML.validate_html(html, [NoInlineStyle])
    end

    test "returns an issue for an element with an inline style attribute" do
      html = ~s(<div style="display: none">Menu</div>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [NoInlineStyle])

      assert issue.check == NoInlineStyle
      assert issue.message == "expected <div> to avoid inline style attributes"
      assert issue.tag == "div"
      assert issue.snippet =~ "<div"
      assert issue.snippet =~ ~s(style="display: none")
    end

    test "returns an issue for an empty inline style attribute" do
      html = ~s(<button style="">Save</button>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [NoInlineStyle])

      assert issue.check == NoInlineStyle
      assert issue.message == "expected <button> to avoid inline style attributes"
      assert issue.tag == "button"
      assert issue.snippet =~ ~s(style="")
    end

    test "returns every inline style issue in document order" do
      html = """
      <section style="margin: 0">
        <p class="copy">Intro</p>
        <button style="color: red">Save</button>
      </section>
      """

      assert {:error, issues} = HTML.validate_html(html, [NoInlineStyle])

      assert [
               %Issue{check: NoInlineStyle, tag: "section", snippet: first_snippet},
               %Issue{check: NoInlineStyle, tag: "button", snippet: second_snippet}
             ] = issues

      assert first_snippet =~ ~s(style="margin: 0")
      assert second_snippet =~ ~s(style="color: red")
    end
  end
end
