defmodule Bylaw.Ecto.Query.Branches do
  @moduledoc false

  @doc """
  Merges two branch lists by combining every left branch with every right branch.

  Use this for `and` expressions, where facts from both sides are true together.
  When the left side is `nil`, the right branches are returned unchanged. This
  is useful while reducing a list of query clauses before the first branch set
  has been initialized.
  """
  @spec merge(list(term()) | nil, list(term()), (term(), term() -> term())) :: list(term())
  def merge(nil, branches, _merge_fun), do: branches

  def merge(left_branches, right_branches, merge_fun) do
    for left <- left_branches, right <- right_branches do
      merge_fun.(left, right)
    end
  end

  @doc """
  Appends one branch list to another.

  Use this for `or` expressions, where each side represents an alternative path
  through the query. When the left side is `nil`, the right branches are returned
  unchanged so reducers can initialize branch state lazily.
  """
  @spec concat(list(term()) | nil, list(term())) :: list(term())
  def concat(nil, branches), do: branches
  def concat(left_branches, right_branches), do: left_branches ++ right_branches

  @doc """
  Returns the set members present in every branch set.

  This is the usual final reduction for checks that track fields through boolean
  branches. If there are no branches, an empty set is returned.
  """
  @spec guaranteed_sets(list(MapSet.t(term()))) :: MapSet.t(term())
  def guaranteed_sets([first | rest]), do: Enum.reduce(rest, first, &MapSet.intersection/2)
  def guaranteed_sets([]), do: MapSet.new()

  @doc """
  Returns the values present in every branch list.

  Values are compared with `MapSet`, so duplicates are discarded. If there are
  no branches, an empty list is returned.
  """
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
