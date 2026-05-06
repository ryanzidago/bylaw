defmodule Bylaw.Credo.Check.PreferEmptyListChecksTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.PreferEmptyListChecks

  test "reports comparisons against empty lists" do
    """
    defmodule Example do
      def compare(items) do
        one = items == []
        two = [] === items
        three = items != []
        four = [] !== items
        {one, two, three, four}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEmptyListChecks)
    |> assert_issues(4)
    |> assert_issues_match([
      %{line_no: 3, trigger: "==", message: ~r/Enum\.empty\?/},
      %{line_no: 4, trigger: "===", message: ~r/Enum\.empty\?/},
      %{line_no: 5, trigger: "!=", message: ~r/Enum\.any\?/},
      %{line_no: 6, trigger: "!==", message: ~r/Enum\.any\?/}
    ])
  end

  test "does not report Enum helpers or empty list pattern matches" do
    """
    defmodule Example do
      def compare(items) do
        empty? = Enum.empty?(items)
        any? = Enum.any?(items)

        result =
          case items do
            [] -> :empty
            _ -> :filled
          end

        {empty?, any?, result}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferEmptyListChecks)
    |> refute_issues()
  end
end
