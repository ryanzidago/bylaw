defmodule Bylaw.Credo.Check.HEEx.RequireLinkHrefTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireLinkHref

  test "reports missing href in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a>Read more</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkHref)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<a",
      message: "Anchor tags must define an href attribute. Use a button for actions."
    })
  end

  test "does not report static href" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href="/articles">Read more</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkHref)
    |> refute_issues()
  end

  test "does not report dynamic href expression" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a href={@path}>Read more</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkHref)
    |> refute_issues()
  end

  test "does not report when root attrs are present" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a {@attrs}>Read more</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkHref)
    |> refute_issues()
  end

  test "reports missing href in single-line H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H"<a>Read more</a>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkHref)
    |> assert_issue(%{line_no: 3, trigger: "<a"})
  end

  test "handles multiple anchor tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <a>Missing one</a>
        <a href="/ok">Present</a>
        <a>Missing two</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkHref)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<a"},
      %{line_no: 6, trigger: "<a"}
    ])
  end

  test "does not report local component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.a>Read more</.a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkHref)
    |> refute_issues()
  end

  test "does not report remote component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <A>Read more</A>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireLinkHref)
    |> refute_issues()
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
    |> run_check(RequireLinkHref)
    |> refute_issues()
  end

  test "reports missing href in html.heex files" do
    """
    <section>
      <a>Missing</a>
      <a href="/ok">Present</a>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireLinkHref)
    |> assert_issue(%{line_no: 2, trigger: "<a"})
  end

  test "does not report allowed href forms in html.heex files" do
    """
    <section>
      <a href="/articles">Static</a>
      <a href={@path}>Dynamic</a>
      <a {@attrs}>Root attrs</a>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireLinkHref)
    |> refute_issues()
  end
end
