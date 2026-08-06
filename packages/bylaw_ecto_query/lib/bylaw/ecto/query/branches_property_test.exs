defmodule Bylaw.Ecto.Query.BranchesPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bylaw.Ecto.Query.Branches

  property "merging branches produces every left and right pairing" do
    check all(
            left_branches <- list_of(integer(), max_length: 8),
            right_branches <- list_of(integer(), max_length: 8)
          ) do
      merged = Branches.merge(left_branches, right_branches, &{&1, &2})

      assert merged == for(left <- left_branches, right <- right_branches, do: {left, right})
      assert Enum.count(merged) == Enum.count(left_branches) * Enum.count(right_branches)
    end
  end

  property "merge produces the cartesian product in left-major order" do
    check all(
            left <- list_of(list_of(integer(), max_length: 4), max_length: 4),
            right <- list_of(list_of(integer(), max_length: 4), max_length: 4)
          ) do
      expected = for left_branch <- left, right_branch <- right, do: left_branch ++ right_branch

      assert Branches.merge(left, right, &Kernel.++/2) == expected
      assert Enum.count(expected) == Enum.count(left) * Enum.count(right)
    end
  end

  property "concat preserves every initialized branch in order" do
    check all(
            left <- list_of(list_of(integer(), max_length: 4), max_length: 4),
            right <- list_of(list_of(integer(), max_length: 4), max_length: 4)
          ) do
      concatenated = Branches.concat(left, right)

      assert Enum.take(concatenated, Enum.count(left)) == left
      assert Enum.drop(concatenated, Enum.count(left)) == right
      assert Enum.count(concatenated) == Enum.count(left) + Enum.count(right)
    end
  end

  property "guaranteed sets contain exactly the values present in every branch" do
    check all(
            branches <- nonempty(list_of(uniq_list_of(integer(), max_length: 8), max_length: 8))
          ) do
      guaranteed = branches |> Enum.map(&MapSet.new/1) |> Branches.guaranteed_sets()
      observed_values = branches |> List.flatten() |> MapSet.new()

      assert MapSet.subset?(guaranteed, observed_values)

      assert Enum.all?(observed_values, fn value ->
               MapSet.member?(guaranteed, value) ==
                 Enum.all?(branches, &Enum.member?(&1, value))
             end)
    end
  end

  property "guaranteed sets are unchanged when branches are reordered or duplicated" do
    check all(
            branches <- nonempty(list_of(uniq_list_of(integer(), max_length: 8), max_length: 8))
          ) do
      sets = Enum.map(branches, &MapSet.new/1)
      expected = Branches.guaranteed_sets(sets)

      assert Branches.guaranteed_sets(Enum.reverse(sets)) == expected
      assert Branches.guaranteed_sets(sets ++ sets) == expected
    end
  end

  property "guaranteed values contain exactly the distinct values present in every branch" do
    check all(branches <- nonempty(list_of(list_of(integer(), max_length: 8), max_length: 8))) do
      guaranteed = branches |> Branches.guaranteed_values() |> MapSet.new()
      observed_values = branches |> List.flatten() |> MapSet.new()

      assert MapSet.subset?(guaranteed, observed_values)

      assert Enum.all?(observed_values, fn value ->
               MapSet.member?(guaranteed, value) ==
                 Enum.all?(branches, &Enum.member?(&1, value))
             end)
    end
  end

  property "guaranteed values are unchanged when values and branches are reordered or duplicated" do
    check all(branches <- nonempty(list_of(list_of(integer(), max_length: 8), max_length: 8))) do
      expected = branches |> Branches.guaranteed_values() |> MapSet.new()
      reordered_values = Enum.map(branches, &Enum.reverse/1)
      duplicated_values = Enum.map(branches, &(&1 ++ &1))

      assert reordered_values |> Branches.guaranteed_values() |> MapSet.new() == expected
      assert duplicated_values |> Branches.guaranteed_values() |> MapSet.new() == expected

      assert branches |> Enum.reverse() |> Branches.guaranteed_values() |> MapSet.new() ==
               expected

      assert branches |> Kernel.++(branches) |> Branches.guaranteed_values() |> MapSet.new() ==
               expected
    end
  end
end
