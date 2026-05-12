defmodule Bylaw.HTML.Check.RequireLinkHrefTest do
  use ExUnit.Case, async: true

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.RequireLinkHref
  alias Bylaw.HTML.Issue

  describe "validate_html/2 with RequireLinkHref" do
    test "passes anchors with href" do
      html = """
      <a href="/settings">Settings</a>
      <a href="">Current page</a>
      """

      assert :ok = HTML.validate_html(html, [RequireLinkHref])
    end

    test "returns an issue for an anchor without href" do
      html = ~s(<a>Settings</a>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [RequireLinkHref])

      assert issue.check == RequireLinkHref
      assert issue.message == "expected <a> to define href; use <button> for actions"
      assert issue.tag == "a"
      assert issue.snippet =~ "<a"
      assert issue.snippet =~ "Settings"
    end

    test "returns an issue for phx-click anchors without href" do
      html = ~s(<a phx-click="save">Save</a>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [RequireLinkHref])

      assert issue.check == RequireLinkHref
      assert issue.snippet =~ ~s(phx-click="save")
    end

    test "returns every missing href issue in document order" do
      html = """
      <a>Settings</a>
      <a href="/users">Users</a>
      <a phx-click="save">Save</a>
      """

      assert {:error, issues} = HTML.validate_html(html, [RequireLinkHref])

      assert [
               %Issue{check: RequireLinkHref, tag: "a", snippet: first_snippet},
               %Issue{check: RequireLinkHref, tag: "a", snippet: second_snippet}
             ] = issues

      assert first_snippet =~ "Settings"
      assert second_snippet =~ "Save"
    end
  end
end
