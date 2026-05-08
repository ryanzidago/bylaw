defmodule Bylaw.Credo.Check.Elixir.NoTryRescueTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NoTryRescue

  test "reports try/rescue blocks" do
    """
    defmodule Example do
      def run do
        try do
          :ok
        rescue
          _ -> :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoTryRescue)
    |> assert_issue()
  end

  test "reports try/catch blocks" do
    """
    defmodule Example do
      def run do
        try do
          throw(:foo)
        catch
          :foo -> :caught
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoTryRescue)
    |> assert_issue()
  end

  test "allows try/after blocks (resource cleanup)" do
    """
    defmodule Example do
      def run do
        try do
          :ok
        after
          :cleanup
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoTryRescue)
    |> refute_issues()
  end

  test "reports try/rescue+after blocks" do
    """
    defmodule Example do
      def run do
        try do
          :ok
        rescue
          _ -> :error
        after
          :cleanup
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoTryRescue)
    |> assert_issue()
  end

  test "does not report code without try blocks" do
    """
    defmodule Example do
      def run do
        case :ok do
          :ok -> :ok
          _ -> :error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(NoTryRescue)
    |> refute_issues()
  end
end
