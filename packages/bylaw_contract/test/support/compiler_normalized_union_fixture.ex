defmodule Bylaw.Contract.TestFixtures.CompilerNormalizedUnionTarget do
  @moduledoc false

  def normalized(:ok), do: :ok
  def normalized(value) when is_atom(value), do: value
  def normalized(value) when is_integer(value), do: value

  def independent(:left), do: :left
  def independent(:right), do: :right

  def merged(:one), do: {:ok, :one}
  def merged(:two), do: {:ok, :two}
  def merged(:error), do: :error
end
