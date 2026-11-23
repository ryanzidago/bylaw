defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStylingTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoElementStyling

  @fix "pages don't style elements. Use a component from the component library, or add one there first."

  test "reports a literal class on a raw element in an H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="flex gap-2">Content</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementStyling)
    |> assert_issue(%{line_no: 4, trigger: "class"})
  end

  test "reports a style attribute on a raw element" do
    """
    <p style="color: red">Archived</p>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> assert_issue(%{line_no: 1, column: 4, trigger: "style"})
  end

  test "reports a class whose value is an expression" do
    """
    <span class={[@tone, "text-sm"]}>Tag</span>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> assert_issue(%{line_no: 1, trigger: "class"})
  end

  test "reports a class on a raw element in a .html.heex template" do
    """
    <section>
      <div class="p-4">Content</div>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> assert_issue(%{line_no: 2, trigger: "class"})
  end

  test "reports each styling attribute on the same element separately" do
    """
    <div class="p-4" style="color: red">Content</div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> assert_issues_match([
      %{line_no: 1, trigger: "class"},
      %{line_no: 1, trigger: "style"}
    ])
  end

  test "the message names the attribute, the element and the fix" do
    """
    <div class="p-4">Content</div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> assert_issue(%{message: "class on <div>: #{@fix}"})
  end

  test "does not report a raw element without styling attributes" do
    """
    <div>
      <p>Content</p>
    </div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> refute_issues()
  end

  test "does not report a class on a component tag" do
    """
    <.button class="px-4">Save</.button>
    <Layouts.app class="mb-14">Content</Layouts.app>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> refute_issues()
  end

  test "does not report a class on a slot tag" do
    """
    <.table rows={@rows}>
      <:col class="w-8" label="Name">Name</:col>
    </.table>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> refute_issues()
  end

  test "does not report other attributes, such as id, href or data-*" do
    """
    <a id="home" href="/" data-role="nav" aria-label="Home">Home</a>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling)
    |> refute_issues()
  end

  test "reports only the attributes named in :attributes" do
    """
    <div class="p-4" style="color: red" hidden>Content</div>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling, attributes: ["style"])
    |> assert_issue(%{trigger: "style"})
  end

  test "reports nothing for a file at its ceiling" do
    two_styled()
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling, ceilings: %{"lib/example/index.html.heex" => 2})
    |> refute_issues()
  end

  test "reports every attribute for a file above its ceiling" do
    two_styled()
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling, ceilings: %{"lib/example/index.html.heex" => 1})
    |> assert_issues_match([
      %{line_no: 1, trigger: "class", message: "class on <div>: " <> @fix},
      %{line_no: 2, trigger: "style", message: "style on <p>: " <> @fix}
    ])
  end

  test "asks to lower the ceiling for a file below it" do
    two_styled()
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling, ceilings: %{"lib/example/index.html.heex" => 5})
    |> assert_issue(%{
      message:
        "This file has 2 styling attributes and its ceiling is 5. Lower the ceiling to 2 in .credo.exs."
    })
  end

  test "asks to remove the ceiling for a file with nothing left" do
    "<div><p>Content</p></div>\n"
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling, ceilings: %{"lib/example/index.html.heex" => 3})
    |> assert_issue(%{
      message: "This file has no styling attributes left. Remove its ceiling from .credo.exs."
    })
  end

  test "a file without a ceiling has a ceiling of zero" do
    two_styled()
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling, ceilings: %{"lib/other/index.html.heex" => 2})
    |> assert_issues(2)
  end

  test "matches a ceiling path written with a leading ./" do
    two_styled()
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoElementStyling, ceilings: %{"./lib/example/index.html.heex" => 2})
    |> refute_issues()
  end

  test "counts the styling attributes of every H sigil in a file" do
    """
    defmodule Example do
      def one(assigns) do
        ~H\"\"\"
        <div class="a">One</div>
        \"\"\"
      end

      def two(assigns) do
        ~H\"\"\"
        <div class="b">Two</div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoElementStyling, ceilings: %{"lib/example.ex" => 2})
    |> refute_issues()
  end

  test "rejects a ceiling that is not a non-negative integer" do
    source_file = Credo.SourceFile.parse("<p></p>\n", "lib/example/index.html.heex")

    for ceilings <- [
          %{"lib/a.ex" => -1},
          %{"lib/a.ex" => :erlang.float(1)},
          %{"lib/a.ex" => "3"},
          %{a: 1},
          [1]
        ] do
      assert_raise ArgumentError, ~r/:ceilings must/, fn ->
        NoElementStyling.run(source_file, ceilings: ceilings)
      end
    end
  end

  defp two_styled do
    """
    <div class="p-4">Content</div>
    <p style="color: red">Archived</p>
    """
  end
end
