defmodule Bylaw.Credo.Check.Phoenix.URIDecodeQueryTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Phoenix.URIDecodeQuery

  test "reports URI.decode_query" do
    """
    defmodule Example do
      def run(query_string) do
        URI.decode_query(query_string)
      end
    end
    """
    |> to_source_file()
    |> run_check(URIDecodeQuery)
    |> assert_issue()
  end

  test "does not report Plug.Conn.Query.decode" do
    """
    defmodule Example do
      def run(query_string) do
        Plug.Conn.Query.decode(query_string)
      end
    end
    """
    |> to_source_file()
    |> run_check(URIDecodeQuery)
    |> refute_issues()
  end
end
