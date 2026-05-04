defmodule Bylaw.Credo.Check.PreferRepoAggregateCountTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.PreferRepoAggregateCount

  test "reports count patterns that materialize rows with Repo.all" do
    """
    defmodule Example do
      alias MyApp.Repo

      def count(query) do
        one = Enum.count(Repo.all(query))
        two = length(Repo.all(query))
        three = Kernel.length(Repo.all(query))
        four = Repo.all(query) |> Enum.count()
        five = Repo.all(query) |> length()
        six = query |> Repo.all() |> Enum.count()
        seven = query |> Repo.all(prefix: "private") |> Kernel.length()

        {one, two, three, four, five, six, seven}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoAggregateCount)
    |> assert_issues(7)
    |> assert_issues_match([
      %{line_no: 5, trigger: "Enum.count", message: ~r/Repo\.aggregate/},
      %{line_no: 6, trigger: "length", message: ~r/Repo\.aggregate/},
      %{line_no: 7, trigger: "Kernel.length", message: ~r/Repo\.aggregate/},
      %{line_no: 8, trigger: "Enum.count", message: ~r/Repo\.aggregate/},
      %{line_no: 9, trigger: "length", message: ~r/Repo\.aggregate/},
      %{line_no: 10, trigger: "Enum.count", message: ~r/Repo\.aggregate/},
      %{line_no: 11, trigger: "Kernel.length", message: ~r/Repo\.aggregate/}
    ])
  end

  test "does not report aggregate usage or non-repo counts" do
    """
    defmodule Example do
      alias MyApp.Repo

      def count(query, items) do
        direct = Repo.aggregate(query, :count)
        explicit_field = Repo.aggregate(query, :count, :id)
        enum_with_fun = Enum.count(Repo.all(query), & &1.active?)
        plain_items = Enum.count(items)
        other_module = OtherStore.all(query) |> Enum.count()

        {direct, explicit_field, enum_with_fun, plain_items, other_module}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoAggregateCount)
    |> refute_issues()
  end

  test "reports existence checks built on Repo.aggregate count comparisons" do
    """
    defmodule Example do
      alias MyApp.Repo

      def exists?(query) do
        one = Repo.aggregate(query, :count) > 0
        two = Repo.aggregate(query, :count, :id) >= 1
        three = Repo.aggregate(query, :count) != 0
        four = Repo.aggregate(query, :count) == 0
        five = Repo.aggregate(query, :count, :id) < 1
        six = query |> Repo.aggregate(:count) > 0
        seven = 0 < Repo.aggregate(query, :count)
        eight = 1 <= Repo.aggregate(query, :count, :id)
        nine = 0 == Repo.aggregate(query, :count)

        {one, two, three, four, five, six, seven, eight, nine}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoAggregateCount)
    |> assert_issues(9)
    |> assert_issues_match([
      %{line_no: 5, trigger: ">", message: ~r/Repo\.exists/},
      %{line_no: 6, trigger: ">=", message: ~r/Repo\.exists/},
      %{line_no: 7, trigger: "!=", message: ~r/Repo\.exists/},
      %{line_no: 8, trigger: "==", message: ~r/Repo\.exists/},
      %{line_no: 9, trigger: "<", message: ~r/Repo\.exists/},
      %{line_no: 10, trigger: ">", message: ~r/Repo\.exists/},
      %{line_no: 11, trigger: "<", message: ~r/Repo\.exists/},
      %{line_no: 12, trigger: "<=", message: ~r/Repo\.exists/},
      %{line_no: 13, trigger: "==", message: ~r/Repo\.exists/}
    ])
  end

  test "does not report real count comparisons" do
    """
    defmodule Example do
      alias MyApp.Repo

      def enough?(query, threshold) do
        one = Repo.aggregate(query, :count) > 5
        two = Repo.aggregate(query, :count, :id) >= threshold
        three = threshold < Repo.aggregate(query, :count)

        {one, two, three}
      end
    end
    """
    |> to_source_file()
    |> run_check(PreferRepoAggregateCount)
    |> refute_issues()
  end
end
