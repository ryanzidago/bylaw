defmodule Bylaw.Ecto.Query.Branches do
  @moduledoc false

  @doc false
  @spec merge(list(term()) | nil, list(term()), (term(), term() -> term())) :: list(term())
  def merge(nil, branches, _merge_fun), do: branches

  def merge(left_branches, right_branches, merge_fun) do
    for left <- left_branches, right <- right_branches do
      merge_fun.(left, right)
    end
  end

  @doc false
  @spec concat(list(term()) | nil, list(term())) :: list(term())
  def concat(nil, branches), do: branches
  def concat(left_branches, right_branches), do: left_branches ++ right_branches

  @doc false
  @spec guaranteed_sets(list(MapSet.t(term()))) :: MapSet.t(term())
  def guaranteed_sets([first | rest]), do: Enum.reduce(rest, first, &MapSet.intersection/2)
  def guaranteed_sets([]), do: MapSet.new()

  @doc false
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
