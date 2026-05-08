defmodule Bylaw.Credo.Check.HEEx.NoRawColorsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.NoRawColors

  @message "Use a design-system color token instead of a raw color literal."

  test "reports hex colors in static HEEx attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <svg fill="#fff"></svg>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors)
    |> assert_issue(%{
      line_no: 4,
      trigger: "fill",
      message: ~r/#{Regex.escape(@message)} Raw color: "#fff"\./
    })
  end

  test "reports CSS color functions in style attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div style="color: rgb(255 0 0)"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors)
    |> assert_issue(%{
      line_no: 4,
      trigger: "style",
      message: ~r/Raw color: "rgb\(255 0 0\)"/
    })
  end

  test "reports named colors in static color attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <table bgcolor="white"><tr><td>Alert</td></tr></table>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors)
    |> assert_issue(%{line_no: 4, trigger: "bgcolor", message: ~r/Raw color: "white"/})
  end

  test "reports raw Tailwind arbitrary colors in class attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="text-[#ff0000]"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors)
    |> assert_issue(%{
      line_no: 4,
      trigger: "class",
      message: ~r/Raw color: "text-\[#ff0000\]"/
    })
  end

  test "reports Tailwind named color utility classes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="hover:text-white"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors)
    |> assert_issue(%{line_no: 4, trigger: "class", message: ~r/Raw color: "hover:text-white"/})
  end

  test "allows configured design-system token classes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="text-primary bg-surface border-default"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors,
      allowed_colors: ["text-primary", "bg-surface", "border-default"]
    )
    |> refute_issues()
  end

  test "allows configured class entries that would otherwise be raw color utilities" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="text-white"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors, allowed_colors: ["text-white"])
    |> refute_issues()
  end

  test "allows configured static attribute tokens" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <svg fill="brand-primary" stroke="var(--color-primary)"></svg>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors, allowed_colors: ["brand-primary", "var(--color-primary)"])
    |> refute_issues()
  end

  test "does not report dynamic color attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <svg fill={@fill} stroke={@stroke} class={@class}></svg>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoRawColors)
    |> refute_issues()
  end

  test "reports raw colors in html.heex files" do
    """
    <section>
      <div class="text-blue-600"></div>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoRawColors)
    |> assert_issue(%{line_no: 2, trigger: "class", message: ~r/Raw color: "text-blue-600"/})
  end
end
