defmodule Bylaw.Credo.Check.FilterRejectFirstTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.FilterRejectFirst

  # --- Enum.filter |> List.first ---

  test "reports piped Enum.filter |> List.first" do
    """
    defmodule Example do
      def find(list) do
        list
        |> Enum.filter(&(&1.active?))
        |> List.first()
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> assert_issue()
  end

  test "reports Enum.filter(...) |> List.first()" do
    """
    defmodule Example do
      def find(list) do
        Enum.filter(list, &(&1.active?))
        |> List.first()
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> assert_issue()
  end

  test "reports List.first(Enum.filter(...))" do
    """
    defmodule Example do
      def find(list) do
        List.first(Enum.filter(list, &(&1.active?)))
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> assert_issue()
  end

  # --- Enum.reject |> List.first ---

  test "reports piped Enum.reject |> List.first" do
    """
    defmodule Example do
      def find(list) do
        list
        |> Enum.reject(&(&1.archived?))
        |> List.first()
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> assert_issue()
  end

  test "reports Enum.reject(...) |> List.first()" do
    """
    defmodule Example do
      def find(list) do
        Enum.reject(list, &(&1.archived?))
        |> List.first()
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> assert_issue()
  end

  test "reports List.first(Enum.reject(...))" do
    """
    defmodule Example do
      def find(list) do
        List.first(Enum.reject(list, &(&1.archived?)))
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> assert_issue()
  end

  # --- No false positives ---

  test "does not report Enum.find/2" do
    """
    defmodule Example do
      def find(list) do
        Enum.find(list, &(&1.active?))
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> refute_issues()
  end

  test "does not report Enum.filter without List.first" do
    """
    defmodule Example do
      def all_active(list) do
        Enum.filter(list, &(&1.active?))
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> refute_issues()
  end

  test "does not report List.first without Enum.filter/reject" do
    """
    defmodule Example do
      def first(list) do
        List.first(list)
      end
    end
    """
    |> to_source_file()
    |> run_check(FilterRejectFirst)
    |> refute_issues()
  end
end
