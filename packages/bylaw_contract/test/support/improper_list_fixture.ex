defmodule Bylaw.Contract.ImproperListFixture do
  @moduledoc false

  @doc false
  @spec echo(list(integer())) :: list(integer()) | :unused
  def echo(value), do: value
end
