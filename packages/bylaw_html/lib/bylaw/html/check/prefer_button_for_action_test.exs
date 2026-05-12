defmodule Bylaw.HTML.Check.PreferButtonForActionTest do
  use ExUnit.Case, async: true

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.PreferButtonForAction
  alias Bylaw.HTML.Issue

  describe "validate_html/2 with PreferButtonForAction" do
    test "passes navigation anchors" do
      html = """
      <a href="/settings">Settings</a>
      <a href="/settings" phx-click="track">Settings</a>
      <a href="#details">Details</a>
      """

      assert :ok = HTML.validate_html(html, [PreferButtonForAction])
    end

    test "passes buttons with phx-click actions" do
      html = ~s(<button type="button" phx-click="save">Save</button>)

      assert :ok = HTML.validate_html(html, [PreferButtonForAction])
    end

    test "passes anchors without phx-click even when href is a fragment placeholder" do
      html = ~s(<a href="#">Back to top</a>)

      assert :ok = HTML.validate_html(html, [PreferButtonForAction])
    end

    test "returns an issue for phx-click anchors with hash href" do
      html = ~s(<a href="#" phx-click="save">Save</a>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [PreferButtonForAction])

      assert issue.check == PreferButtonForAction

      assert issue.message ==
               "expected action links to use <button>; found <a> with phx-click and action href"

      assert issue.tag == "a"
      assert issue.snippet =~ ~s(href="#")
      assert issue.snippet =~ ~s(phx-click="save")
    end

    test "returns an issue for phx-click anchors with empty href" do
      html = ~s(<a href="" phx-click="open">Open</a>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [PreferButtonForAction])

      assert issue.check == PreferButtonForAction
      assert issue.snippet =~ ~s(href="")
      assert issue.snippet =~ ~s(phx-click="open")
    end

    test "returns an issue for phx-click anchors with javascript void href" do
      html = ~S|<a href="javascript:void(0);" phx-click="save">Save</a>|

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [PreferButtonForAction])

      assert issue.check == PreferButtonForAction
      assert issue.snippet =~ "javascript:void(0);"
    end

    test "returns every action link issue in document order" do
      html = """
      <a href="#" phx-click="save">Save</a>
      <a href="/settings" phx-click="track">Settings</a>
      <a href="" phx-click="open">Open</a>
      """

      assert {:error, issues} = HTML.validate_html(html, [PreferButtonForAction])

      assert [
               %Issue{check: PreferButtonForAction, tag: "a", snippet: first_snippet},
               %Issue{check: PreferButtonForAction, tag: "a", snippet: second_snippet}
             ] = issues

      assert first_snippet =~ "Save"
      assert second_snippet =~ "Open"
    end
  end
end
