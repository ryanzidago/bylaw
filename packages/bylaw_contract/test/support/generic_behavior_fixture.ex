defmodule ContractCompatibility.Types do
  @moduledoc false
  @type action :: :return | :raise | :throw | :exit
  @type mode :: :normal | :quiet
end

defmodule ContractCompatibility.Payload do
  @moduledoc false
  defstruct [:flag]
  @type t :: %__MODULE__{flag: :present | :empty}
end

defprotocol ContractCompatibility.Label do
  @doc false
  @spec label(t()) :: :present | :empty
  def label(value)
end

defimpl ContractCompatibility.Label, for: ContractCompatibility.Payload do
  @doc false
  @spec label(ContractCompatibility.Payload.t()) :: :present | :empty
  def label(%{flag: :present}), do: :present
  def label(%{flag: :empty}), do: :empty
end

defmodule ContractCompatibility.Actions do
  @moduledoc false
  alias ContractCompatibility.{Label, Payload, Types}

  @doc false
  @spec perform(Types.action(), pid()) :: :ok | :unused
  def perform(:return, destination) do
    send(destination, {self(), :body, :return})
    :ok
  end

  def perform(:raise, destination) do
    send(destination, {self(), :body, :raise})
    raise ArgumentError, "fixture raise"
  end

  def perform(:throw, destination) do
    send(destination, {self(), :body, :throw})
    throw(:fixture_throw)
  end

  def perform(:exit, destination) do
    send(destination, {self(), :body, :exit})
    exit(:fixture_exit)
  end

  @doc false
  @spec label(Payload.t(), Types.mode()) :: :present | :empty
  def label(value, mode \\ :normal)
  def label(%Payload{} = value, :normal), do: Label.label(value)
  def label(%Payload{}, :quiet), do: :empty
end
