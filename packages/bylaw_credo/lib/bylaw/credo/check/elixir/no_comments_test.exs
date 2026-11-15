defmodule Bylaw.Credo.Check.Elixir.NoCommentsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoComments

  test "reports a comment on its own line" do
    """
    defmodule Sample do
      # Adds one.
      def add_one(number), do: number + 1
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoComments)
    |> assert_issue(fn issue ->
      assert issue.line_no == 2
      assert issue.trigger == "# Adds one."
      assert issue.message =~ "@moduledoc"
    end)
  end

  test "reports a comment at the end of a line" do
    """
    defmodule Sample do
      def add_one(number), do: number + 1 # adds one
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoComments)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end

  test "allows Credo directives by default" do
    """
    # credo:disable-for-this-file Credo.Check.Readability.Specs
    defmodule Sample do
      # credo:disable-for-next-line Bylaw.Credo.Check.Elixir.NoRaise
      def boom, do: raise("boom")

      #credo:disable-for-next-definition Bylaw.Credo.Check.HEEx.RequireButtonType
      def other, do: :ok
    end
    """
    |> to_source_file("lib/sample.ex")
    |> run_check(NoComments)
    |> refute_issues()
  end

  test "reports other tool directives unless they are allowed" do
    source = """
    defmodule Migration do
      # excellent_migrations:safety-assured-for-next-line raw_sql_executed
      def change, do: execute("SELECT 1")
    end
    """

    source
    |> to_source_file("priv/repo/migrations/1_migration.exs")
    |> run_check(NoComments)
    |> assert_issue()

    source
    |> to_source_file("priv/repo/migrations/1_migration.exs")
    |> run_check(NoComments, allowed_directives: ["credo:", "excellent_migrations:"])
    |> refute_issues()
  end

  test "allows a shebang on the first line" do
    """
    #!/usr/bin/env elixir
    IO.puts("hello")
    """
    |> to_source_file("script.exs")
    |> run_check(NoComments)
    |> refute_issues()
  end

  test "ignores comment-like text in strings, heredocs, charlists and sigils" do
    ~S'''
    defmodule Sample do
      @moduledoc """
      # Not a comment
      """

      def values(name) do
        [
          "# not a comment #{name}",
          ~c"# not a comment",
          ~r/# not a comment/,
          ~S(<!-- not HEEx -->),
          "<%!-- not HEEx --%>"
        ]
      end
    end
    '''
    |> to_source_file("lib/sample.ex")
    |> run_check(NoComments)
    |> refute_issues()
  end

  test "reports HEEx comments inside a ~H sigil" do
    ~S'''
    defmodule SampleWeb do
      def card(assigns) do
        ~H"""
        <div id="cart">
          <%!-- Server comment --%>
          <!-- HTML comment -->
        </div>
        """
      end
    end
    '''
    |> to_source_file("lib/sample_web.ex")
    |> run_check(NoComments)
    |> assert_issues(fn issues ->
      line_numbers =
        issues
        |> Enum.map(& &1.line_no)
        |> Enum.sort()

      assert line_numbers == [5, 6]
    end)
  end

  test "reports HEEx comments in a .html.heex template" do
    """
    <main>
      <%!-- multi
        line --%>
      <p>Hello</p>
    </main>
    """
    |> Credo.SourceFile.parse("lib/sample_web/page.html.heex")
    |> run_check(NoComments)
    |> assert_issue(fn issue -> assert issue.line_no == 2 end)
  end
end
