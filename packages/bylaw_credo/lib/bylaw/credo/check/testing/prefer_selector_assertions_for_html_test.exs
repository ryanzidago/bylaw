defmodule Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtmlTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.PreferSelectorAssertionsForHtml

  test "reports HTML substring assertions with multiple selector attributes" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders the control" do
        html = render_component(&control/1, %{})
        assert html =~ ~s(<button id="save" phx-click="save">Save</button>)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> assert_issue(%{line_no: 6, trigger: "assert"})
  end

  test "reports exact HTML equality assertions with multiple selector attributes" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders the status" do
        assert render_status() == ~s(<span class="success" aria-live="polite">Saved</span>)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> assert_issue()
  end

  test "reports selector attributes separated by unrelated attributes and whitespace" do
    ~S'''
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders the row" do
        assert html =~ """
        <div
          id="account-1"
          title="Primary account"
          data-account-id="1"
        >Account</div>
        """
      end
    end
    '''
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> assert_issue(%{line_no: 5})
  end

  @doc """
  Issue: A greater-than sign inside a double-quoted attribute value causes tag
  scanning to stop before later selector attributes.

  Why it matters: Valid HTML assertions can evade the check and remain coupled
  to unstable serialized attribute order.
  """
  test "reports selector attributes after a greater-than sign in a double-quoted value" do
    ~S'''
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders the control" do
        assert html =~ ~s(<button title="1 > 0" id="save" phx-click="save">Save</button>)
      end
    end
    '''
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> assert_issue(%{line_no: 5, trigger: "assert"})
  end

  @doc """
  Issue: A greater-than sign inside a single-quoted attribute value causes tag
  scanning to stop before later selector attributes.

  Why it matters: The check should recognize selector-relevant attributes in
  valid HTML regardless of which HTML quote style surrounds another value.
  """
  test "reports selector attributes after a greater-than sign in a single-quoted value" do
    ~S'''
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders the control" do
        assert html =~ ~s(<button title='1 > 0' id="save" phx-click="save">Save</button>)
      end
    end
    '''
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> assert_issue(%{line_no: 5, trigger: "assert"})
  end

  @doc """
  Issue: Quote-aware tag scanning could count selector-looking text inside an
  attribute value as real attributes.

  Why it matters: HTML with only one selector attribute should not produce a
  false-positive Credo failure because another value contains HTML-like text.
  """
  test "does not count selector-looking text inside a quoted attribute value" do
    ~S'''
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders the control" do
        assert html =~ ~s(<button title='id="decoy" > class="decoy"' phx-click="save">Save</button>)
      end
    end
    '''
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> refute_issues()
  end

  test "reports each brittle HTML assertion at its assertion call" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders controls" do
        assert html =~ ~s(<button id="save" class="primary">Save</button>)
        refute html =~ ~s(<button id="cancel" data-role="cancel">Cancel</button>)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 5, trigger: "assert"},
      %{line_no: 6, trigger: "refute"}
    ])
  end

  test "recognizes phx, data, aria, id, and class selector attributes" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders selector contracts" do
        assert html =~ ~s(<button phx-click="save" data-role="submit">Save</button>)
        assert html =~ ~s(<div aria-live="polite" id="status">Saved</div>)
        assert html =~ ~s(<section class="panel" data-state="open">Open</section>)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> assert_issues(3)
  end

  test "does not report assertions with one selector attribute" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders the control" do
        assert html =~ ~s(<button id="save" type="button">Save</button>)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> refute_issues()
  end

  test "does not report selector-based assertions" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "renders the control" do
        assert has_element?(view, "#save.primary[phx-click=save]")
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> refute_issues()
  end

  test "does not report serialized HTML assigned as fixture data" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      test "parses the fixture" do
        html = ~s(<div id="notice" class="info">Hello</div>)
        assert parse(html)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> refute_issues()
  end

  test "does not report assertions outside test files" do
    """
    defmodule Example do
      def validate(html) do
        assert html =~ ~s(<div id="notice" class="info">Hello</div>)
      end
    end
    """
    |> to_source_file("lib/example.ex")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> refute_issues()
  end

  test "does not report HTML-like text in comments" do
    """
    defmodule ExampleTest do
      use ExUnit.Case

      # assert html =~ ~s(<div id="notice" class="info">Hello</div>)
      test "passes", do: assert(true)
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml)
    |> refute_issues()
  end

  test "respects excluded paths" do
    """
    defmodule GeneratedTest do
      use ExUnit.Case

      test "renders generated markup" do
        assert html =~ ~s(<div id="notice" class="info">Hello</div>)
      end
    end
    """
    |> to_source_file("test/generated/example_test.exs")
    |> run_check(PreferSelectorAssertionsForHtml, excluded_paths: ["test/generated/"])
    |> refute_issues()
  end
end
