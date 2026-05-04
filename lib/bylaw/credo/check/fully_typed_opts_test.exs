defmodule Bylaw.Credo.Check.FullyTypedOptsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.FullyTypedOpts

  test "reports broad opts parameter types in specs and callbacks" do
    """
    defmodule Example do
      @callback search(query :: String.t(), opts :: keyword()) :: :ok
      @spec fetch(query :: String.t(), request_opts :: Keyword.t()) :: :ok
      def fetch(_query, _request_opts), do: :ok
    end
    """
    |> to_source_file()
    |> run_check(FullyTypedOpts)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 2, trigger: "opts :: keyword()", message: ~r/Fully type option lists/},
      %{
        line_no: 3,
        trigger: "request_opts :: Keyword.t()",
        message: ~r/concrete `\*_opts\(\)` alias/
      }
    ])
  end

  test "reports broad *_opts type aliases" do
    """
    defmodule Example do
      @type search_opts :: keyword()
      @opaque request_opts :: Keyword.t()
    end
    """
    |> to_source_file()
    |> run_check(FullyTypedOpts)
    |> assert_issues(2)
    |> assert_issues_match([
      %{line_no: 2, trigger: "search_opts :: keyword()"},
      %{line_no: 3, trigger: "request_opts :: Keyword.t()"}
    ])
  end

  test "does not report non-opts keyword params, concrete opts aliases, or returns" do
    """
    defmodule Example do
      @type search_opt :: {:max_results, pos_integer()}
      @type search_opts :: [search_opt()]

      @spec search(query :: String.t(), opts :: search_opts()) :: keyword()
      @spec init(params :: keyword()) :: keyword()
      def search(_query, _opts), do: []
      def init(params), do: params
    end
    """
    |> to_source_file()
    |> run_check(FullyTypedOpts)
    |> refute_issues()
  end

  test "respects excluded_paths" do
    "defmodule Example do\n  @spec search(query :: String.t(), opts :: keyword()) :: :ok\nend\n"
    |> to_source_file("lib/bylaw/repo.ex")
    |> run_check(FullyTypedOpts, excluded_paths: ["lib/bylaw/repo.ex"])
    |> refute_issues()
  end
end
