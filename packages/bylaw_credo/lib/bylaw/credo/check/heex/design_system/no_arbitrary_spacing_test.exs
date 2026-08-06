defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacingTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.DesignSystem.NoArbitrarySpacing

  @message "Use a design-system spacing token instead of a raw pixel spacing value."

  test "reports arbitrary pixel margin classes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="m-[18px]"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issue(%{
      line_no: 4,
      trigger: "class",
      message: ~r/#{Regex.escape(@message)} Raw spacing: "m-\[18px\]"\./
    })
  end

  test "reports arbitrary pixel padding and gap classes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="p-[22px] gap-[13px]"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "class", message: ~r/Raw spacing: "p-\[22px\]"/},
      %{line_no: 4, trigger: "class", message: ~r/Raw spacing: "gap-\[13px\]"/}
    ])
  end

  test "reports directional, variant, and negative arbitrary pixel spacing classes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="-mt-[8px] md:px-[12px] hover:gap-x-[10px]"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issues(3)
    |> assert_issues_match([
      %{message: ~r/Raw spacing: "-mt-\[8px\]"/},
      %{message: ~r/Raw spacing: "md:px-\[12px\]"/},
      %{message: ~r/Raw spacing: "hover:gap-x-\[10px\]"/}
    ])
  end

  test "reports pixel values inside arbitrary spacing expressions" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="m-[calc(100%-18px)]"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issue(%{
      line_no: 4,
      trigger: "class",
      message: ~r/Raw spacing: "m-\[calc\(100%-18px\)\]"/
    })
  end

  test "reports arbitrary pixel space utilities" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="space-x-[18px] md:space-y-[22px]"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "class", message: ~r/Raw spacing: "space-x-\[18px\]"/},
      %{line_no: 4, trigger: "class", message: ~r/Raw spacing: "md:space-y-\[22px\]"/}
    ])
  end

  test "reports pixel values with omitted leading zero" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="m-[.5px]" style="margin: .75px"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "class", message: ~r/Raw spacing: "m-\[\.5px\]"/},
      %{line_no: 4, trigger: "style", message: ~r/Raw spacing: "margin: \.75px"/}
    ])
  end

  test "reports raw pixel margin and padding declarations in style attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div style="margin: 18px; padding-inline: 2rem; padding-top: 22px; margin-inline: 14px"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 4, trigger: "style", message: ~r/Raw spacing: "margin: 18px"/},
      %{line_no: 4, trigger: "style", message: ~r/Raw spacing: "padding-top: 22px"/},
      %{line_no: 4, trigger: "style", message: ~r/Raw spacing: "margin-inline: 14px"/}
    ])
  end

  test "does not report design-system spacing utilities or tokenized styles" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="m-4 p-6 gap-3 md:px-2 p-[var(--space-18px)]" style="margin: var(--space-4); padding: 1rem"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> refute_issues()
  end

  test "does not report non-spacing arbitrary classes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class="top-[18px] w-[22px]"></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> refute_issues()
  end

  test "does not report dynamic class or style values" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <div class={@class} style={@style}></div>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> refute_issues()
  end

  test "reports arbitrary spacing in html.heex files" do
    """
    <section>
      <div class="m-[18px]"></div>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issue(%{line_no: 2, trigger: "class", message: ~r/Raw spacing: "m-\[18px\]"/})
  end

  test "reports arbitrary spacing on component attributes" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <.button class="p-[22px]">Save</.button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(NoArbitrarySpacing)
    |> assert_issue(%{line_no: 4, trigger: "class", message: ~r/Raw spacing: "p-\[22px\]"/})
  end
end
