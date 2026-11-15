defmodule Bylaw.Credo.Check.HEEx.NoUntranslatedTextTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.HEEx.NoUntranslatedText

  test "reports literal text in a ~H sigil, with its line" do
    ~S'''
    defmodule SampleWeb do
      def card(assigns) do
        ~H"""
        <div>
          <p>Hello guest</p>
        </div>
        """
      end
    end
    '''
    |> to_source_file("lib/sample_web.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issue(fn issue ->
      assert issue.line_no == 5
      assert issue.trigger == "Hello guest"
      assert issue.message =~ "gettext"
    end)
  end

  test "reports letters from any script, including brand names" do
    ~S'''
    defmodule SampleWeb do
      def card(assigns) do
        ~H"""
        <p>Größe</p>
        <span>Acme</span>
        """
      end
    end
    '''
    |> to_source_file("lib/sample_web.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issues(2)
  end

  test "allows expressions, symbols, digits, entities, comments, script and style" do
    ~S'''
    defmodule SampleWeb do
      def card(assigns) do
        ~H"""
        <p class="price total" id="sum">{gettext("Total")}: {@total} €</p>
        <span>– · × % 12,50 (3) → &nbsp; &rarr;</span>
        <%= @name %>
        <%!-- A HEEx comment --%>
        <!-- An HTML comment -->
        <a href="/menu" data-role="link" phx-click="open">{@label}</a>
        <script>window.greeting = "hello";</script>
        <style>body::after { content: "text"; }</style>
        """
      end
    end
    '''
    |> to_source_file("lib/sample_web.ex")
    |> run_check(NoUntranslatedText)
    |> refute_issues()
  end

  test "reports user-visible attributes and ignores the rest" do
    ~S'''
    defmodule SampleWeb do
      def form(assigns) do
        ~H"""
        <img src="/logo.png" alt="Logo" />
        <input type="text" name="email" placeholder="Your email" value="draft" />
        <input type="submit" value="Send" />
        <button type="submit" value="save" aria-label="Save order">{gettext("Save")}</button>
        <.button value="true" phx-disable-with="Saving…">{gettext("Save")}</.button>
        <.input field={@form[:email]} label="Email" title={gettext("Email")} />
        """
      end
    end
    '''
    |> to_source_file("lib/sample_web.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issues(fn issues ->
      triggers =
        issues
        |> Enum.map(& &1.trigger)
        |> Enum.sort()

      assert triggers ==
               Enum.sort([
                 ~s(alt="Logo"),
                 ~s(placeholder="Your email"),
                 ~s(value="Send"),
                 ~s(phx-disable-with="Saving…"),
                 ~s(aria-label="Save order"),
                 ~s(label="Email")
               ])
    end)
  end

  test "checks only the configured visible attributes" do
    ~S'''
    defmodule SampleWeb do
      def form(assigns) do
        ~H"""
        <img src="/logo.png" alt="Logo" title="Company" />
        <span data-tooltip="Hello">{@count}</span>
        """
      end
    end
    '''
    |> to_source_file("lib/sample_web.ex")
    |> run_check(NoUntranslatedText, visible_attributes: ["data-tooltip"])
    |> assert_issue(fn issue -> assert issue.trigger == ~s(data-tooltip="Hello") end)
  end

  test "reports option text" do
    ~S'''
    defmodule SampleWeb do
      def select(assigns) do
        ~H"""
        <select name="size">
          <option value="s">Small</option>
          <option value="m">{gettext("Medium")}</option>
        </select>
        """
      end
    end
    '''
    |> to_source_file("lib/sample_web.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issue(fn issue -> assert issue.trigger == "Small" end)
  end

  test "reports literal text in a .html.heex template" do
    """
    <!DOCTYPE html>
    <main>
      <h1>{@title}</h1>
      <!-- Not text -->
      <p>
        Plain words
      </p>
    </main>
    """
    |> Credo.SourceFile.parse("lib/sample_web/untranslated.html.heex")
    |> run_check(NoUntranslatedText)
    |> assert_issue(fn issue ->
      assert issue.line_no == 6
      assert issue.trigger == "Plain words"
    end)
  end
end
