defmodule Bylaw.Credo.Check.Elixir.PreferListTypeSyntaxTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.PreferListTypeSyntax

  test "reports bracket list syntax in typespecs" do
    """
    defmodule Example do
      @type names :: [String.t()]
      @spec run([integer()]) :: [atom()]
      @callback stringify(term()) :: [String.t()]
      @spec with_constraint(t) :: t when t: [keyword(String.t())]
    end
    """
    |> to_source_file()
    |> run_check(PreferListTypeSyntax)
    |> assert_issues(5)
    |> assert_issues_match([
      %{line_no: 2, trigger: "[String.t()]", message: ~r/list\(String\.t\(\)\)/},
      %{line_no: 3, trigger: "[integer()]", message: ~r/list\(integer\(\)\)/},
      %{line_no: 3, trigger: "[atom()]", message: ~r/list\(atom\(\)\)/},
      %{line_no: 4, trigger: "[String.t()]", message: ~r/list\(String\.t\(\)\)/},
      %{
        line_no: 5,
        trigger: "[keyword(String.t())]",
        message: ~r/list\(keyword\(String\.t\(\)\)\)/
      }
    ])
  end

  test "does not report list/1, empty list types, nonempty list syntax, or runtime lists" do
    """
    defmodule Example do
      @type names :: list(String.t())
      @type empty :: []
      @spec run([integer(), ...]) :: nonempty_list(atom())
      def run(items), do: [items]
    end
    """
    |> to_source_file()
    |> run_check(PreferListTypeSyntax)
    |> refute_issues()
  end

  test "does not report direct function types but still reports real list syntax around them" do
    """
    defmodule Example do
      @spec child_spec((Plug.Conn.t() -> Plug.Conn.t())) :: {Bandit, keyword()}
      @type handlers :: [(Plug.Conn.t() -> Plug.Conn.t())]
      @spec normalize(([String.t()] -> [atom()])) :: [integer()]
    end
    """
    |> to_source_file()
    |> run_check(PreferListTypeSyntax)
    |> assert_issues(4)
    |> assert_issues_match([
      %{
        line_no: 3,
        trigger: "[(Plug.Conn.t() -> Plug.Conn.t())]",
        message: ~r/list\(\(Plug\.Conn\.t\(\) -> Plug\.Conn\.t\(\)\)\)/
      },
      %{line_no: 4, trigger: "[String.t()]", message: ~r/list\(String\.t\(\)\)/},
      %{line_no: 4, trigger: "[atom()]", message: ~r/list\(atom\(\)\)/},
      %{line_no: 4, trigger: "[integer()]", message: ~r/list\(integer\(\)\)/}
    ])
  end
end
