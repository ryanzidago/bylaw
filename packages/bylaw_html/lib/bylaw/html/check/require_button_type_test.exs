defmodule Bylaw.HTML.Check.RequireButtonTypeTest do
  use ExUnit.Case, async: true

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.RequireButtonType
  alias Bylaw.HTML.Issue

  describe "validate_html/2 with RequireButtonType" do
    test "passes buttons with valid type attributes" do
      html = """
      <button type="button" phx-click="save">Save</button>
      <button type="submit">Save</button>
      <button type="reset">Reset</button>
      """

      assert :ok = HTML.validate_html(html, [RequireButtonType])
    end

    test "passes valid type attributes regardless of case and surrounding whitespace" do
      html = ~s(<button type=" Button ">Save</button>)

      assert :ok = HTML.validate_html(html, [RequireButtonType])
    end

    test "returns an issue for a button without a type attribute" do
      html = ~s(<button phx-click="save">Save</button>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [RequireButtonType])

      assert issue.check == RequireButtonType
      assert issue.message == "expected <button> to define a valid type attribute"
      assert issue.tag == "button"
      assert issue.snippet =~ "<button"
      assert issue.snippet =~ ~s(phx-click="save")
    end

    test "returns an issue for a button with an empty type attribute" do
      html = ~s(<button type="">Save</button>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [RequireButtonType])

      assert issue.check == RequireButtonType
      assert issue.snippet =~ ~s(type="")
    end

    test "returns an issue for a button with an invalid type attribute" do
      html = ~s(<button type="save">Save</button>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [RequireButtonType])

      assert issue.check == RequireButtonType
      assert issue.snippet =~ ~s(type="save")
    end

    test "returns every invalid button type issue in document order" do
      html = """
      <button>Save</button>
      <button type="button">Cancel</button>
      <button type="delete">Delete</button>
      """

      assert {:error, issues} = HTML.validate_html(html, [RequireButtonType])

      assert [
               %Issue{check: RequireButtonType, tag: "button", snippet: first_snippet},
               %Issue{check: RequireButtonType, tag: "button", snippet: second_snippet}
             ] = issues

      assert first_snippet =~ "Save"
      assert second_snippet =~ ~s(type="delete")
    end
  end
end
