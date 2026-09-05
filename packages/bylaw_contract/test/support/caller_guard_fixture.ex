defmodule Bylaw.Contract.CallerGuardFixture do
  @moduledoc false

  @doc false
  @spec who(pid()) :: :caller | :other
  def who(pid) when pid == self(), do: :caller
  def who(_), do: :other

  @doc false
  @spec nested(term()) :: :caller | :other
  def nested(value) when :erlang.map_get(:owner, value) == self() when value == self(),
    do: :caller

  def nested(_), do: :other
end
