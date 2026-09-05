defmodule ProducerSemanticFixture do
  def count(0), do: :done
  def count(value) when is_integer(value) and value > 0, do: count(value - 1)

  def captured_count(value) do
    function = &count/1
    function.(value)
  end

  def deliver(value, prefix \\ :default), do: {prefix, value}
  def strict(:allowed), do: :ok
  def choose(value) when is_integer(value) and value > 0, do: :positive
  def choose(value) when is_integer(value), do: :integer
end

defmodule ProducerSemanticPayload do
  defstruct [:value]
end

defprotocol ProducerSemanticProtocol do
  def tag(value)
end

defimpl ProducerSemanticProtocol, for: ProducerSemanticPayload do
  def tag(%{value: value}), do: {:tagged, value}
end
