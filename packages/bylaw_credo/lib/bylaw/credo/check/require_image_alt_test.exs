defmodule Bylaw.Credo.Check.RequireImageAltTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.RequireImageAlt

  test "reports missing alt in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/logo.svg">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<img",
      message: "Images must define an alt attribute. Use alt=\"\" for decorative images."
    })
  end

  test "does not report static alt" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/logo.svg" alt="Company logo">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "reports missing alt in single-line H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H"<img src={@src}>"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issue(%{line_no: 3, trigger: "<img"})
  end

  test "does not report dynamic alt expression" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src={@src} alt={@alt}>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "does not report when root attrs are present" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img {@attrs}>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "reports self-closing img without alt" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/logo.svg" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issue(%{line_no: 4, trigger: "<img"})
  end

  test "handles multiple img tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/one.svg">
        <img src="/two.svg" alt="Two">
        <img src="/three.svg">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<img"},
      %{line_no: 6, trigger: "<img"}
    ])
  end

  test "does not report dynamic component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.image src="/logo.svg" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "does not report remote component tags" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <Image src="/logo.svg" />
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
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
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "does not crash when HEEx cannot be tokenized" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <img src="/logo.svg"
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> refute_issues()
  end

  test "reports missing alt across multiple H sigils" do
    """
    defmodule Example do
      def header(assigns) do
        ~H\"\"\"
        <img src="/header.svg">
        \"\"\"
      end

      def footer(assigns) do
        ~H\"\"\"
        <img src="/footer.svg">
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireImageAlt)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "<img"},
      %{line_no: 10, trigger: "<img"}
    ])
  end

  test "reports missing alt in html.heex files" do
    """
    <section>
      <img src="/logo.svg">
      <img src="/decorative.svg" alt="">
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireImageAlt)
    |> assert_issue(%{line_no: 2, trigger: "<img"})
  end
end
