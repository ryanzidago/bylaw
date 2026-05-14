defmodule Bylaw.HTML.Check.NoDuplicateAttributesTest do
  use ExUnit.Case, async: true

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.NoDuplicateAttributes
  alias Bylaw.HTML.Issue

  describe "validate_html/2 with NoDuplicateAttributes" do
    test "passes elements with unique attributes" do
      html = """
      <div id="content" class="stack" data-role="primary">Content</div>
      <input type="checkbox" checked>
      """

      assert :ok = HTML.validate_html(html, [NoDuplicateAttributes])
    end

    test "returns an issue for duplicate attributes on one element" do
      html = ~s(<div id="primary" id="secondary">Content</div>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [NoDuplicateAttributes])

      assert issue.check == NoDuplicateAttributes
      assert issue.message == "expected <div> to define id only once"
      assert issue.tag == "div"
      assert issue.snippet == ~s(<div id="primary" id="secondary">)
    end

    test "treats attribute names as case-insensitive" do
      html = ~s(<button class="primary" CLASS="secondary">Save</button>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [NoDuplicateAttributes])

      assert issue.check == NoDuplicateAttributes
      assert issue.message == "expected <button> to define class only once"
      assert issue.tag == "button"
    end

    test "returns each duplicate attribute on the same element" do
      html = ~s(<input type="text" name="email" type="email" NAME="contact_email">)

      assert {:error, issues} = HTML.validate_html(html, [NoDuplicateAttributes])

      assert [
               %Issue{message: "expected <input> to define name only once"},
               %Issue{message: "expected <input> to define type only once"}
             ] = issues
    end

    test "returns duplicate attribute issues in document order" do
      html = """
      <div id="one" id="two"></div>
      <button type="button" type="submit">Save</button>
      """

      assert {:error, issues} = HTML.validate_html(html, [NoDuplicateAttributes])

      assert [
               %Issue{tag: "div", message: "expected <div> to define id only once"},
               %Issue{tag: "button", message: "expected <button> to define type only once"}
             ] = issues
    end

    test "ignores tag-like text inside quoted attribute values" do
      html = ~s(<div data-template="<span id='one' id='two'></span>" id="content"></div>)

      assert :ok = HTML.validate_html(html, [NoDuplicateAttributes])
    end

    test "supports unquoted and boolean attributes" do
      html = ~s(<input type=text disabled disabled>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [NoDuplicateAttributes])

      assert issue.message == "expected <input> to define disabled only once"
      assert issue.snippet == ~s(<input type=text disabled disabled>)
    end

    test "supports slash characters in unquoted attribute values" do
      html = ~s(<a href=/settings data-path=/users/1 href=/profile>Profile</a>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [NoDuplicateAttributes])

      assert issue.message == "expected <a> to define href only once"
    end

    test "ignores comments, declarations, closing tags, and processing instructions" do
      html = """
      <!doctype html>
      <!-- <div id="one" id="two"></div> -->
      <?xml version="1.0" version="2.0"?>
      <div id="content"></div>
      </div id="one" id="two">
      """

      assert :ok = HTML.validate_html(html, [NoDuplicateAttributes])
    end
  end
end
