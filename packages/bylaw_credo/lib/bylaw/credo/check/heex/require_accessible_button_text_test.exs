defmodule Bylaw.Credo.Check.HEEx.RequireAccessibleButtonTextTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.RequireAccessibleButtonText

  test "reports empty button in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button"></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> assert_issue(%{
      line_no: 4,
      trigger: "<button",
      message: "Buttons must have text content, aria-label, or aria-labelledby."
    })
  end

  test "reports icon-only button in H sigil" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button">
          <.icon name="hero-x-mark" />
        </button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> assert_issue(%{line_no: 4, trigger: "<button"})
  end

  test "does not report button with static text" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button">Save</button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> refute_issues()
  end

  test "does not report button with nested static text" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button"><span class="sr-only">Close</span><.icon name="hero-x-mark" /></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> refute_issues()
  end

  test "does not report button with static aria-label" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button" aria-label="Close"><.icon name="hero-x-mark" /></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> refute_issues()
  end

  test "reports button with empty aria-label and no content" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button" aria-label="   "><.icon name="hero-x-mark" /></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> assert_issue(%{line_no: 4, trigger: "<button"})
  end

  test "does not report button with aria-labelledby" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <span id="close-label">Close</span>
        <button type="button" aria-labelledby="close-label"><.icon name="hero-x-mark" /></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> refute_issues()
  end

  test "does not report button with dynamic content" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button">{@label}</button>
        <button type="button"><%= @legacy_label %></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> refute_issues()
  end

  test "does not report button with dynamic attrs" do
    """
    defmodule Example do
      def render(assigns) do
        ~H\"\"\"
        <button type="button" {@button_attrs}><.icon name="hero-x-mark" /></button>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(RequireAccessibleButtonText)
    |> refute_issues()
  end

  test "reports empty button in html.heex files" do
    """
    <section>
      <button type="button"></button>
      <button type="button" aria-label="Close"><.icon name="hero-x-mark" /></button>
      <button type="button">Save</button>
    </section>
    """
    |> Credo.SourceFile.parse("lib/example/index.html.heex")
    |> run_check(RequireAccessibleButtonText)
    |> assert_issue(%{line_no: 2, trigger: "<button"})
  end
end
