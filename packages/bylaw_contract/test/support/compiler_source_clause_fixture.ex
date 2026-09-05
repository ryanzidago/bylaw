defmodule Bylaw.Contract.TestFixtures.CompilerSourceClauseTarget do
  @moduledoc false

  def choose({:done, _, _} = value), do: value
  def choose({:discard, value}), do: discard(value)
  def choose({:keep, value}), do: {:keep, value}
  def choose(value), do: discard(value)

  def reordered({:keep, value}), do: {:keep, value}
  def reordered({:done, _, _} = value), do: value
  def reordered({:discard, value}), do: discard(value)
  def reordered(value), do: discard(value)

  def ambiguous(value) when is_integer(value) and value > 0, do: :positive
  def ambiguous(value) when is_integer(value), do: :other

  def independent(:left), do: :left
  def independent(:right), do: :right

  defp discard([]), do: {:done, [], []}

  defp discard(value) when is_list(value) or is_binary(value) do
    key = :binary.compile_pattern(value)
    match = value |> List.wrap() |> Enum.map(&(&1 <> "=")) |> :binary.compile_pattern()
    {:done, key, match}
  end
end
