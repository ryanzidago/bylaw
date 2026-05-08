defmodule Bylaw.Credo.Check.HEEx.RequireLinkTextTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireLinkText

  test "reports empty links in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/settings"></a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<a",
      message: "Links must have accessible text or an accessible name."
    })
  end

  test "does not report non-link anchors" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a id="settings"></a>
        <a name="profile"></a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> refute_issues()
  end

  test "reports icon-only links in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/settings"><.icon name="settings" /></a>
        <a href="/search"><svg><path /></svg></a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<a"},
      %{line_no: 5, trigger: "<a"}
    ])
  end

  test "does not report links with text content" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/settings">Settings</a>
        <a href="/profile"><span>Profile</span></a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> refute_issues()
  end

  test "does not report links with ARIA labels" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/settings" aria-label="Settings"><.icon name="settings" /></a>
        <a href="/profile" aria-labelledby="profile-link-label"><.icon name="user" /></a>
        <a href="/search" aria-label={@search_label}><.icon name="search" /></a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> refute_issues()
  end

  test "reports empty ARIA labels without text content" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/settings" aria-label=""><.icon name="settings" /></a>
        <a href="/profile" aria-labelledby="   "><.icon name="user" /></a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> assert_issues(2)
  end

  test "does not report dynamic link content" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href={@href}>{@label}</a>
        <a href={@href}><%= @label %></a>
        <a {@attrs}></a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> refute_issues()
  end

  test "uses non-empty image alt text as link text" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/home"><img src="/home.svg" alt="Home"></a>
        <a href="/settings"><img src="/settings.svg" alt=""></a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> assert_issues(1)
    |> assert_issue(%{line_no: 5, trigger: "<a"})
  end

  test "reports empty links in html.heex files" do
    """
    <nav>
      <a href="/settings"></a>
      <a href="/profile">Profile</a>
    </nav>
    """
    |> Credo.SourceFile.parse("lib/example/nav.html.heex")
    |> run_check(RequireLinkText)
    |> assert_issues(1)
    |> assert_issue(%{line_no: 2, trigger: "<a"})
  end

  test "checks accessible names in html.heex files" do
    """
    <nav>
      <a href="/settings"><.icon name="settings" /></a>
      <a href="/profile">Profile</a>
      <a href="/search" aria-label="Search"><.icon name="search" /></a>
      <a href={@href}>{@label}</a>
    </nav>
    """
    |> Credo.SourceFile.parse("lib/example/nav.html.heex")
    |> run_check(RequireLinkText)
    |> assert_issues(1)
    |> assert_issue(%{line_no: 2, trigger: "<a"})
  end

  test "does not crash when source has no HEEx" do
    """
    defmodule Example do
      def render(assigns) do
        "not a template"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkText)
    |> refute_issues()
  end
end
