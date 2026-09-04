defmodule Bylaw.Contract.StructuralExample do
  @moduledoc false

  @spec classify(value :: term()) :: :exact | :atom | :positive_integer | :integer | :other
  def classify(:exact), do: :exact
  def classify(value) when is_atom(value), do: :atom
  def classify(value) when is_integer(value) and value > 0, do: :positive_integer
  def classify(value) when is_integer(value), do: :integer
  def classify(_), do: :other

  @spec guarded_only(value :: term()) :: :positive
  def guarded_only(value) when is_integer(value) and value > 0, do: :positive

  @spec optional(value :: term(), suffix :: term()) :: {term(), term()}
  def optional(value, suffix \\ :default)
  def optional(:left, suffix), do: {:left, suffix}
  def optional(value, suffix), do: {value, suffix}

  @spec through_private(value :: term()) :: :private_exact | :private_integer
  def through_private(value), do: private_classify(value)

  @spec through_private_default(value :: term()) :: {term(), :middle, :tail}
  def through_private_default(value), do: private_default(value)

  @spec body_probe(destination :: pid(), value :: term()) :: term()
  def body_probe(destination, value) when is_pid(destination) do
    send(destination, {:body_ran, value})
    value
  end

  defp private_classify(:private_exact), do: :private_exact
  defp private_classify(value) when is_integer(value), do: :private_integer

  defp private_default(value, middle \\ :middle, tail \\ :tail),
    do: {value, middle, tail}
end
