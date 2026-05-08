defmodule Bylaw.Ecto.Query.Branches do
  @moduledoc false

  # `and` expressions combine facts from both sides into the same branch. `nil`
  # lets reducers initialize branch state from the first expression while
  # reducing a list of query clauses.
  @spec merge(list(term()) | nil, list(term()), (term(), term() -> term())) :: list(term())
  def merge(nil, branches, _merge_fun), do: branches

  def merge(left_branches, right_branches, merge_fun) do
    for left <- left_branches, right <- right_branches do
      merge_fun.(left, right)
    end
  end

  # `or` expressions append alternate paths through the query instead of
  # merging facts into a single branch. `nil` again means the branch accumulator
  # has not been initialized yet.
  @spec concat(list(term()) | nil, list(term())) :: list(term())
  def concat(nil, branches), do: branches
  def concat(left_branches, right_branches), do: left_branches ++ right_branches

  # Checks use this after boolean branch analysis to keep only facts guaranteed
  # by every possible branch. No branches means no guaranteed set members.
  @spec guaranteed_sets(list(MapSet.t(term()))) :: MapSet.t(term())
  def guaranteed_sets([first | rest]), do: Enum.reduce(rest, first, &MapSet.intersection/2)
  def guaranteed_sets([]), do: MapSet.new()

  # Values are compared through MapSet so duplicate observations do not affect
  # the guaranteed value list. No branches means no guaranteed values.
  @spec guaranteed_values(list(list(term()))) :: list(term())
  def guaranteed_values([first | rest]) do
    rest
    |> Enum.reduce(MapSet.new(first), fn values, guaranteed ->
      MapSet.intersection(guaranteed, MapSet.new(values))
    end)
    |> MapSet.to_list()
  end

  def guaranteed_values([]), do: []
end
