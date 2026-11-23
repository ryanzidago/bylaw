defmodule Bylaw.Credo.Check.Elixir.NoUntranslatedTextTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoUntranslatedText
  alias Credo.Check.ConfigComment

  test "reports a literal flash message with its line, text and a gettext hint" do
    """
    defmodule Sample do
      def save(socket) do
        put_flash(socket, :info, "Saved")
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issue(fn issue ->
      assert issue.line_no == 3
      assert issue.trigger == "Saved"
      assert issue.message =~ "\"Saved\""
      assert issue.message =~ "gettext"
      assert issue.message =~ "put_flash/3"
    end)
  end

  test "reports a flash message in a piped call and in a remote call" do
    """
    defmodule Sample do
      def a(conn), do: conn |> put_flash(:error, "Try again")
      def b(conn), do: Phoenix.Controller.put_flash(conn, :error, "Sign in first")
      def c(conn), do: conn |> Phoenix.Controller.put_flash(:info, "Signed out")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {2, "Try again"},
               {3, "Sign in first"},
               {4, "Signed out"}
             ]
    end)
  end

  test "reports an interpolated string and a heredoc with interpolation" do
    ~S'''
    defmodule Sample do
      def a(socket, name), do: put_flash(socket, :info, "Saved #{name}")

      def b(socket, name) do
        put_flash(socket, :info, """
        Hello #{name},
        your order is on its way.
        """)
      end
    end
    '''
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {2, "Saved \#{…}"},
               {5, "Hello \#{…}, your order is on its way."}
             ]
    end)
  end

  test "reports a literal joined with <>" do
    """
    defmodule Sample do
      def a(socket, name), do: put_flash(socket, :info, "Saved " <> name)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issue(fn issue -> assert issue.trigger == "Saved" end)
  end

  test "reports letters from any script" do
    """
    defmodule Sample do
      def a(socket), do: put_flash(socket, :info, "Größe")
      def b(socket), do: put_flash(socket, :info, "保存しました")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issues(2)
  end

  test "reports a literal assigned to the page title, in each form of assign" do
    """
    defmodule Sample do
      def a(socket), do: assign(socket, :page_title, "Orders")
      def b(socket), do: assign(socket, page_title: "Menus")
      def c(socket), do: assign(socket, %{page_title: "Guests"})
      def d(socket), do: socket |> assign(:page_title, "Status")
      def e(socket), do: socket |> assign(page_title: "Account", refreshes: 0)
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["Orders", "Menus", "Guests", "Status", "Account"]
    end)
  end

  test "reports only the assign keys it is given" do
    """
    defmodule Sample do
      def a(socket), do: assign(socket, :heading, "Orders")
      def b(socket), do: assign(socket, :page_title, "Menus")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText, assign_keys: [:heading])
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.trigger == "Orders"
    end)
  end

  test "allows assigns of other keys, expressions and a title from gettext" do
    """
    defmodule Sample do
      def a(socket), do: assign(socket, :mode, "edit")
      def b(socket), do: assign(socket, page_title: gettext("Orders"))
      def c(socket, menu), do: assign(socket, page_title: menu.name)
      def d(socket), do: assign(socket, %{status: "open", page_title: @title})
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> refute_issues()
  end

  test "reports the configured sinks, by name and arity, in the positions given" do
    """
    defmodule Sample do
      def a(user, url) do
        deliver(user.email, "Reset your password", "Open the link: \#{url}")
      end

      def b(user), do: deliver(user.email, gettext("Hello"), "Plain words")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText, sinks: [{:deliver, 3, [2, 3]}])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, &{&1.line_no, &1.trigger}) == [
               {3, "Reset your password"},
               {3, "Open the link: \#{…}"},
               {6, "Plain words"}
             ]
    end)
  end

  test "replaces the default sinks when sinks are given" do
    """
    defmodule Sample do
      def a(socket), do: put_flash(socket, :info, "Saved")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText, sinks: [{:deliver, 3, [2]}])
    |> refute_issues()
  end

  test "matches a sink with a module only on a call that names that module, aliases resolved" do
    """
    defmodule Sample do
      alias MyApp.Flash, as: F

      def a(conn), do: MyApp.Flash.show(conn, "Saved")
      def b(conn), do: F.show(conn, "Deleted")
      def c(conn), do: Other.show(conn, "Ignored")
      def d(conn), do: show(conn, "Ignored too")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText, sinks: [{MyApp.Flash, :show, 2, [2]}])
    |> assert_issues(fn issues ->
      assert Enum.map(issues, & &1.trigger) == ["Saved", "Deleted"]
    end)
  end

  test "matches a sink without a module with any module and with a local call" do
    """
    defmodule Sample do
      def a(conn), do: Phoenix.Controller.put_flash(conn, :info, "Saved")
      def b(conn), do: put_flash(conn, :info, "Deleted")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issues(2)
  end

  test "does not match a call of another arity" do
    """
    defmodule Sample do
      def a(socket), do: put_flash(socket, "Saved")
      def b(socket), do: socket |> put_flash(:info, "Saved", "extra")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> refute_issues()
  end

  test "allows text from gettext, variables, attributes and functions" do
    """
    defmodule Sample do
      @saved "Saved"

      def a(socket), do: put_flash(socket, :info, gettext("Saved"))
      def b(socket), do: put_flash(socket, :info, dgettext("flash", "Saved"))
      def c(socket, text), do: put_flash(socket, :info, text)
      def d(socket), do: put_flash(socket, :info, @saved)
      def e(socket, reason), do: put_flash(socket, :error, ErrorText.message(reason))
      def f(socket), do: put_flash(socket, :info, gettext("Saved %{name}", name: "Ann"))
      def g(socket), do: socket |> put_flash(:info, gettext_noop("Saved"))
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> refute_issues()
  end

  test "allows strings without a letter" do
    """
    defmodule Sample do
      def a(socket), do: put_flash(socket, :info, "")
      def b(socket), do: put_flash(socket, :info, "12,50 € · 3 × 4 → 5%")
      def c(socket, count), do: put_flash(socket, :info, "\#{count} - \#{count}")
      def d(socket), do: put_flash(socket, :info, "…")
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> refute_issues()
  end

  test "does not look at calls that are not sinks" do
    """
    defmodule Sample do
      require Logger

      def a(conn) do
        Logger.info("Saved the order")
        raise ArgumentError, "Saved the order"
        redirect(conn, to: "/orders")
        Map.get(conn.params, "saved")
        %{"label" => "Orders", "error" => "Saved"}
        assign(conn, :mode, "Saved")
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> refute_issues()
  end

  test "does not report the head of a function that has a sink's name" do
    """
    defmodule Sample do
      def put_flash(conn, :info, "Saved"), do: conn
      defp put_flash(conn, :error, "Failed") when is_map(conn), do: conn
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> refute_issues()
  end

  test "reports on the call's line, so Credo's disable-for-next-line comment silences it" do
    issues =
      """
      defmodule Sample do
        def a(socket) do
          # credo:disable-for-next-line Bylaw.Credo.Check.Elixir.NoUntranslatedText
          put_flash(socket, :info, "Deutsch")
        end

        def b(socket) do
          put_flash(socket, :info, "English")
        end
      end
      """
      |> to_source_file("lib/sample.ex")
      |> run_check(NoUntranslatedText)

    comment =
      ConfigComment.new(
        "disable-for-next-line",
        inspect(NoUntranslatedText),
        3
      )

    assert [kept] = Enum.reject(issues, &ConfigComment.ignores_issue?(comment, &1))
    assert kept.trigger == "English"
  end

  test "reports a sink inside a nested function, case and with" do
    """
    defmodule Sample do
      def a(socket, result) do
        case result do
          :ok -> put_flash(socket, :info, "Saved")
          :error -> Enum.map([1], fn _ -> put_flash(socket, :error, "Failed") end)
        end
      end
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoUntranslatedText)
    |> assert_issues(2)
  end
end
