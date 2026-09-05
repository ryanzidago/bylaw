defmodule Bylaw.Contract.StructuralJointFixture do
  @moduledoc false

  @doc false
  @spec map_value(term()) :: atom()
  def map_value(%{payload: payload}) when :erlang.map_get(:ok, payload) == true, do: :ok
  def map_value(%{payload: payload}) when is_map(payload), do: :map
  def map_value(%{payload: _}), do: :payload
  def map_value(_), do: :other

  @doc false
  @spec alternative(term()) :: atom()
  def alternative(value) when map_size(value) > 0 when is_atom(value), do: :accepted
  def alternative(_), do: :other

  @doc false
  @spec repeated(term()) :: atom()
  def repeated({value, value}) when is_integer(value), do: :equal_integer
  def repeated({_, _}), do: :pair
  def repeated(_), do: :other

  @doc false
  @spec bytes(term()) :: atom()
  def bytes(<<size, payload::binary-size(size)>>) when byte_size(payload) > 0, do: :nonempty
  def bytes(<<_size, _payload::binary>>), do: :other_binary
  def bytes(_), do: :other
end
