defmodule Bylaw.HTML.Check.RequireImageAltTest do
  use ExUnit.Case, async: true

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.RequireImageAlt
  alias Bylaw.HTML.Issue

  describe "validate_html/2 with RequireImageAlt" do
    test "passes images with alt text" do
      html = ~s(<img src="/logo.svg" alt="Company logo">)

      assert :ok = HTML.validate_html(html, [RequireImageAlt])
    end

    test "passes decorative images with empty alt" do
      html = ~s(<img src="/spacer.svg" alt="">)

      assert :ok = HTML.validate_html(html, [RequireImageAlt])
    end

    test "returns an issue for an image without alt" do
      html = ~s(<img src="/logo.svg">)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [RequireImageAlt])

      assert issue.check == RequireImageAlt
      assert issue.message == ~s(expected <img> to define alt; use alt="" for decorative images)
      assert issue.tag == "img"
      assert issue.snippet =~ "<img"
      assert issue.snippet =~ ~s(src="/logo.svg")
    end

    test "returns every missing alt issue in document order" do
      html = """
      <img src="/logo.svg">
      <img src="/avatar.jpg" alt="User avatar">
      <img src="/hero.jpg">
      """

      assert {:error, issues} = HTML.validate_html(html, [RequireImageAlt])

      assert [
               %Issue{check: RequireImageAlt, tag: "img", snippet: first_snippet},
               %Issue{check: RequireImageAlt, tag: "img", snippet: second_snippet}
             ] = issues

      assert first_snippet =~ ~s(src="/logo.svg")
      assert second_snippet =~ ~s(src="/hero.jpg")
    end
  end
end
