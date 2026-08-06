defmodule Bylaw.Credo.Check.Ecto.PreferOrderByOverRepoAllEnumSortTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.PreferOrderByOverRepoAllEnumSort

  test "reports piped Repo.all followed by Enum.sort" do
    """
    defmodule Example do
      alias MyApp.Repo

      def sorted(query) do
        query |> Repo.all() |> Enum.sort()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferOrderByOverRepoAllEnumSort)
    |> assert_issue(%{trigger: "Enum.sort", message: ~r/order_by/})
  end

  test "reports piped Repo.all followed by Enum.sort_by" do
    """
    defmodule Example do
      alias MyApp.Repo

      def sorted(query) do
        query |> Repo.all() |> Enum.sort_by(& &1.inserted_at)
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferOrderByOverRepoAllEnumSort)
    |> assert_issue(%{trigger: "Enum.sort_by", message: ~r/order_by/})
  end

  test "reports non-piped Repo.all sorting forms" do
    """
    defmodule Example do
      alias MyApp.Repo

      def sorted(query) do
        one = Repo.all(query) |> Enum.sort()
        two = Enum.sort(Repo.all(query))
        {one, two}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferOrderByOverRepoAllEnumSort)
    |> assert_issues(2)
  end

  test "reports qualified Repo modules and Repo.all options" do
    """
    defmodule Example do
      def sorted(query) do
        query |> MyApp.Repo.all(prefix: "private") |> Enum.sort()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferOrderByOverRepoAllEnumSort)
    |> assert_issue(%{trigger: "Enum.sort"})
  end

  test "allows intermediate transformations before sorting" do
    """
    defmodule Example do
      alias MyApp.Repo

      def sorted(query) do
        query |> Repo.all() |> Enum.map(& &1.name) |> Enum.sort()
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferOrderByOverRepoAllEnumSort)
    |> refute_issues()
  end

  test "allows unrelated sorting" do
    """
    defmodule Example do
      def sorted(values, query) do
        one = Enum.sort(values)
        two = query |> OtherRepo.all() |> Enum.sort()
        {one, two}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferOrderByOverRepoAllEnumSort)
    |> refute_issues()
  end
end
