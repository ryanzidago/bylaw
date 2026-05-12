defmodule Bylaw.HTMLTest do
  use ExUnit.Case, async: true

  doctest Bylaw.HTML

  alias Bylaw.HTML
  alias Bylaw.HTML.Check.PreferLinkForNavigation
  alias Bylaw.HTML.Issue

  defmodule PassingCheck do
    @behaviour Bylaw.HTML.Check

    @doc false
    @impl Bylaw.HTML.Check
    @spec validate(Bylaw.HTML.Check.context()) :: Bylaw.HTML.Check.result()
    def validate(_context), do: :ok
  end

  defmodule CustomMainCheck do
    @behaviour Bylaw.HTML.Check

    @doc false
    @impl Bylaw.HTML.Check
    @spec validate(Bylaw.HTML.Check.context()) :: Bylaw.HTML.Check.result()
    def validate(%{document: document}) do
      if document |> LazyHTML.query("main") |> Enum.empty?() do
        {:error,
         [
           %Issue{
             check: __MODULE__,
             message: "expected rendered HTML to include a <main> element",
             tag: "main"
           }
         ]}
      else
        :ok
      end
    end
  end

  defmodule InvalidReturnCheck do
    @behaviour Bylaw.HTML.Check

    @doc false
    @impl Bylaw.HTML.Check
    @spec validate(Bylaw.HTML.Check.context()) :: term()
    def validate(_context), do: :error
  end

  defmodule EmptyIssueCheck do
    @behaviour Bylaw.HTML.Check

    @doc false
    @impl Bylaw.HTML.Check
    @spec validate(Bylaw.HTML.Check.context()) :: {:error, list(Issue.t())}
    def validate(_context), do: {:error, []}
  end

  defmodule InvalidIssueCheck do
    @behaviour Bylaw.HTML.Check

    @doc false
    @impl Bylaw.HTML.Check
    @spec validate(Bylaw.HTML.Check.context()) :: {:error, list(term())}
    def validate(_context), do: {:error, [:bad]}
  end

  describe "validate_html/2" do
    test "returns :ok for empty checks" do
      assert :ok = HTML.validate_html("<button>", [])
    end

    test "passes valid anchor navigation with href" do
      html = ~s(<a href="/settings">Settings</a>)

      assert :ok = HTML.validate_html(html, [PreferLinkForNavigation])
    end

    test "passes valid rendered anchor navigation using data-phx-link" do
      html = ~s(<a href="/users" data-phx-link="patch" data-phx-link-state="push">Users</a>)

      assert :ok = HTML.validate_html(html, [PreferLinkForNavigation])
    end

    test "passes anchor elements with phx-click navigation commands" do
      html =
        ~s(<a href="/settings" phx-click='[["navigate",{"href":"/settings","replace":false}]]'>Settings</a>)

      assert :ok = HTML.validate_html(html, [PreferLinkForNavigation])
    end

    test "passes non-navigation phx-click strings" do
      html = ~s(<button phx-click="save">Save</button>)

      assert :ok = HTML.validate_html(html, [PreferLinkForNavigation])
    end

    test "passes non-navigation phx-click JSON sequences" do
      html = ~s(<button phx-click='[["push",{"event":"save"}]]'>Save</button>)

      assert :ok = HTML.validate_html(html, [PreferLinkForNavigation])
    end

    test "returns an issue for button navigate commands" do
      html =
        ~s(<button phx-click='[["navigate",{"href":"/settings","replace":false}]]'>Settings</button>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [PreferLinkForNavigation])

      assert issue.check == PreferLinkForNavigation

      assert issue.message ==
               "expected durable navigation to use <a>; found phx-click navigate on <button>"

      assert issue.tag == "button"
      assert issue.snippet =~ "<button"
      assert issue.snippet =~ "navigate"
    end

    test "returns an issue for div patch commands" do
      html = ~s(<div phx-click='[["patch",{"href":"/users","replace":false}]]'>Users</div>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [PreferLinkForNavigation])

      assert issue.check == PreferLinkForNavigation

      assert issue.message ==
               "expected durable navigation to use <a>; found phx-click patch on <div>"

      assert issue.tag == "div"
    end

    test "returns an issue for mixed command sequences containing navigate" do
      html =
        ~s(<span phx-click='[["push",{"event":"track"}],["navigate",{"href":"/reports","replace":false}]]'>Reports</span>)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [PreferLinkForNavigation])

      assert issue.check == PreferLinkForNavigation

      assert issue.message ==
               "expected durable navigation to use <a>; found phx-click navigate on <span>"

      assert issue.tag == "span"
    end

    test "ignores malformed and non-json phx-click values" do
      html = """
      <button phx-click="save">Save</button>
      <button phx-click='[["navigate",{"href":"/settings"}]'>Broken</button>
      <button phx-click='{"event":"save"}'>Object</button>
      """

      assert :ok = HTML.validate_html(html, [PreferLinkForNavigation])
    end

    test "returns every issue found in one HTML string" do
      html = """
      <button phx-click='[["navigate",{"href":"/settings","replace":false}]]'>Settings</button>
      <div phx-click='[["patch",{"href":"/users","replace":false}]]'>Users</div>
      """

      assert {:error, issues} = HTML.validate_html(html, [PreferLinkForNavigation])

      assert [
               %Issue{
                 check: PreferLinkForNavigation,
                 tag: "button",
                 message:
                   "expected durable navigation to use <a>; found phx-click navigate on <button>"
               },
               %Issue{
                 check: PreferLinkForNavigation,
                 tag: "div",
                 message: "expected durable navigation to use <a>; found phx-click patch on <div>"
               }
             ] = issues

      assert Enum.all?(issues, &is_binary(&1.snippet))
    end

    test "does not crash on malformed HTML input" do
      html =
        ~s(<section><button phx-click='[["navigate",{"href":"/settings","replace":false}]]'>Settings)

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [PreferLinkForNavigation])

      assert issue.check == PreferLinkForNavigation
      assert issue.tag == "button"
    end

    test "accepts downstream custom check modules" do
      html = "<div>content</div>"

      assert {:error, [%Issue{} = issue]} = HTML.validate_html(html, [CustomMainCheck])

      assert issue.check == CustomMainCheck
      assert issue.message == "expected rendered HTML to include a <main> element"
      assert issue.tag == "main"
    end

    test "raises when a check returns an invalid result" do
      assert_raise ArgumentError,
                   "expected #{inspect(InvalidReturnCheck)}.validate/1 to return :ok or {:error, non_empty_issue_list}, got: :error",
                   fn ->
                     HTML.validate_html("<div />", [InvalidReturnCheck])
                   end

      assert_raise ArgumentError,
                   "expected #{inspect(EmptyIssueCheck)}.validate/1 to return :ok or {:error, non_empty_issue_list}, got: {:error, []}",
                   fn ->
                     HTML.validate_html("<div />", [EmptyIssueCheck])
                   end

      assert_raise ArgumentError,
                   "expected #{inspect(InvalidIssueCheck)}.validate/1 to return :ok or {:error, non_empty_issue_list}, got: {:error, [:bad]}",
                   fn ->
                     HTML.validate_html("<div />", [InvalidIssueCheck])
                   end
    end

    test "raises when checks are not a list" do
      assert_raise ArgumentError, "expected checks to be a list, got: :bad", fn ->
        HTML.validate_html("<div />", :bad)
      end
    end

    test "raises when a check is not an HTML check module" do
      assert_raise ArgumentError, "expected String to be an HTML check module", fn ->
        HTML.validate_html("<div />", [String])
      end
    end

    test "raises when html is not a string" do
      assert_raise ArgumentError, "expected html to be a string, got: :bad", fn ->
        HTML.validate_html(:bad, [PassingCheck])
      end
    end
  end
end
