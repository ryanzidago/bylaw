defmodule Bylaw.Credo.Check.PhoenixLiveView.RequireFunctionComponentAttrsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.PhoenixLiveView.RequireFunctionComponentAttrs

  test "reports an undeclared assign in a public function component" do
    """
    defmodule Example do
      def card(assigns) do
        ~H\"\"\"
        <h2>{@title}</h2>
        \"\"\"
      end
    end
    """
    |> run_check()
    |> assert_issue(%{
      line_no: 4,
      trigger: "@title",
      message:
        "Function component `card/1` uses caller-facing assign `@title` without an `attr :title` or `slot :title` declaration."
    })
  end

  test "reports an undeclared assign in a private function component" do
    """
    defmodule Example do
      defp card(assigns), do: ~H\"<p>{@title}</p>\"
    end
    """
    |> run_check()
    |> assert_issue(%{line_no: 2, trigger: "@title"})
  end

  test "reports each undeclared assign once at its first use" do
    """
    defmodule Example do
      attr :declared, :string

      def card(assigns) do
        ~H\"\"\"
        <p>{@missing}</p>
        <p>{@declared} {@missing} {@other}</p>
        \"\"\"
      end
    end
    """
    |> run_check()
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 6, trigger: "@missing"},
      %{line_no: 7, trigger: "@other"}
    ])
  end

  test "accepts declared attributes and slots" do
    """
    defmodule Example do
      attr :title, :string, required: true
      slot :header
      slot :inner_block

      def card(assigns) do
        ~H\"\"\"
        <h2>{@title}</h2>
        <header :if={@header != []}>{render_slot(@header)}</header>
        {render_slot(@inner_block)}
        \"\"\"
      end
    end
    """
    |> run_check()
    |> refute_issues()
  end

  test "requires render_slot assigns to use slot declarations" do
    """
    defmodule Example do
      attr :inner_block, :any

      def card(assigns) do
        ~H\"{render_slot(@inner_block)}\"
      end
    end
    """
    |> run_check()
    |> assert_issue(%{
      trigger: "@inner_block",
      message:
        "Function component `card/1` renders `@inner_block` without a `slot :inner_block` declaration."
    })
  end

  test "accepts assigns created internally with assign" do
    """
    defmodule Example do
      def direct(assigns) do
        assigns = assign(assigns, :title, "Direct")
        ~H\"<p>{@title}</p>\"
      end

      def keyword(assigns) do
        assigns = assign(assigns, title: "Keyword", count: 1)
        ~H\"<p>{@title} {@count}</p>\"
      end

      def piped(assigns) do
        assigns = assigns |> assign(:title, "Piped") |> assign(count: 1)
        ~H\"<p>{@title} {@count}</p>\"
      end

      def mapped(assigns) do
        assigns = assign(assigns, %{title: "Mapped", count: 1})
        ~H\"<p>{@title} {@count}</p>\"
      end
    end
    """
    |> run_check()
    |> refute_issues()
  end

  test "requires declarations for assigns initialized with assign_new" do
    """
    defmodule Example do
      def card(assigns) do
        assigns = assign_new(assigns, :title, fn -> "Fallback" end)
        ~H\"<p>{@title}</p>\"
      end
    end
    """
    |> run_check()
    |> assert_issue(%{trigger: "@title"})
  end

  test "always excludes render/1" do
    """
    defmodule ExampleLive do
      def render(assigns) do
        ~H\"<h1>{@page_title}</h1>\"
      end
    end
    """
    |> run_check()
    |> refute_issues()
  end

  test "ignores functions that are not arity-one HEEx components" do
    """
    defmodule Example do
      def label(value), do: value
      def pair(left, right), do: ~H\"<p>{@missing}</p>\"
      def zero(), do: ~H\"<p>{@missing}</p>\"
    end
    """
    |> run_check()
    |> refute_issues()
  end

  test "associates declarations with only the next function" do
    """
    defmodule Example do
      attr :title, :string
      def first(assigns), do: ~H\"<p>{@title}</p>\"

      def second(assigns), do: ~H\"<p>{@title}</p>\"
    end
    """
    |> run_check()
    |> assert_issue(%{line_no: 5, trigger: "@title"})
  end

  test "shares declarations across clauses of the same component" do
    """
    defmodule Example do
      attr :title, :string

      def card(%{title: "short"} = assigns), do: ~H\"<p>{@title}</p>\"
      def card(assigns), do: ~H\"<h2>{@title}</h2>\"
    end
    """
    |> run_check()
    |> refute_issues()
  end

  test "keeps declarations scoped to their module" do
    """
    defmodule First do
      attr :title, :string
      def card(assigns), do: ~H\"<p>{@title}</p>\"
    end

    defmodule Second do
      def card(assigns), do: ~H\"<p>{@title}</p>\"
    end
    """
    |> run_check()
    |> assert_issue(%{line_no: 7, trigger: "@title"})
  end

  test "checks terminal HEEx templates in conditional branches" do
    """
    defmodule Example do
      def card(assigns) do
        if assigns[:compact] do
          ~H\"<p>{@short_title}</p>\"
        else
          ~H\"<h2>{@long_title}</h2>\"
        end
      end
    end
    """
    |> run_check()
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 4, trigger: "@short_title"},
      %{line_no: 6, trigger: "@long_title"}
    ])

    """
    defmodule Example do
      def card(assigns) do
        case assigns[:kind] do
          :short -> ~H\"<p>{@case_title}</p>\"
          :long -> ~H\"<h2>{@other_case_title}</h2>\"
        end
      end
    end
    """
    |> run_check()
    |> assert_issues(2)
  end

  test "does not treat an incidental non-returned HEEx sigil as a component" do
    """
    defmodule Example do
      def helper(assigns) do
        template = ~H\"<p>{@title}</p>\"
        {:ok, template}
      end
    end
    """
    |> run_check()
    |> refute_issues()
  end

  test "does not crash on invalid source or unavailable HEEx templates" do
    """
    defmodule Example do
      def card(assigns) do
        ~H\"\"\"
        <div class={@title>
        \"\"\"
      end
    end
    """
    |> run_check()
    |> refute_issues()

    "<p>{@title}</p>"
    |> Credo.SourceFile.parse("lib/example.html.heex")
    |> run_check(RequireFunctionComponentAttrs)
    |> refute_issues()
  end

  defp run_check(source) do
    source
    |> to_source_file("lib/example.ex")
    |> run_check(RequireFunctionComponentAttrs)
  end
end
