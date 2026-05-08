defmodule Bylaw.Credo.Check.Elixir.RejectCountTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.RejectCount

  test "reports piped Enum.reject |> Enum.count" do
    """
    defmodule Example do
      def count(list) do
        list
        |> Enum.reject(&(&1.status == :inactive))
        |> Enum.count()
      end
    end
    """
    |> to_source_file()
    |> run_check(RejectCount)
    |> assert_issue()
  end

  test "reports Enum.count(Enum.reject(...))" do
    """
    defmodule Example do
      def count(list) do
        Enum.count(Enum.reject(list, &(&1.status == :inactive)))
      end
    end
    """
    |> to_source_file()
    |> run_check(RejectCount)
    |> assert_issue()
  end

  test "does not report Enum.count/2" do
    """
    defmodule Example do
      def count(list) do
        Enum.count(list, &(&1.status != :inactive))
      end
    end
    """
    |> to_source_file()
    |> run_check(RejectCount)
    |> refute_issues()
  end
end
