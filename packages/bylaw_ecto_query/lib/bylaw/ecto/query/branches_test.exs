defmodule Bylaw.Ecto.Query.BranchesTest do
  use ExUnit.Case, async: true

  alias Bylaw.Ecto.Query.Branches

  describe "merge/3" do
    test "uses right branches when left branches are not initialized" do
      branches = [MapSet.new([:organisation_id])]

      assert Branches.merge(nil, branches, &MapSet.union/2) == branches
    end

    test "combines every left branch with every right branch" do
      merged =
        Branches.merge(
          [MapSet.new([:organisation_id]), MapSet.new([:user_id])],
          [MapSet.new([:status]), MapSet.new([:deleted_at])],
          &MapSet.union/2
        )

      assert merged == [
               MapSet.new([:organisation_id, :status]),
               MapSet.new([:organisation_id, :deleted_at]),
               MapSet.new([:user_id, :status]),
               MapSet.new([:user_id, :deleted_at])
             ]
    end
  end

  describe "concat/2" do
    test "uses right branches when left branches are not initialized" do
      branches = [[:status]]

      assert Branches.concat(nil, branches) == branches
    end

    test "appends initialized branch lists" do
      assert Branches.concat([[:status]], [[:deleted_at]]) == [[:status], [:deleted_at]]
    end
  end

  describe "guaranteed_sets/1" do
    test "returns fields present in every branch" do
      branches = [
        MapSet.new([:organisation_id, :status]),
        MapSet.new([:organisation_id, :deleted_at])
      ]

      assert Branches.guaranteed_sets(branches) == MapSet.new([:organisation_id])
    end

    test "returns an empty set for no branches" do
      assert Branches.guaranteed_sets([]) == MapSet.new()
    end
  end

  describe "guaranteed_values/1" do
    test "returns values present in every branch" do
      assert Branches.guaranteed_values([[:status, :deleted_at], [:status]]) == [:status]
    end

    test "returns an empty list for no branches" do
      assert Enum.empty?(Branches.guaranteed_values([]))
    end
  end
end
