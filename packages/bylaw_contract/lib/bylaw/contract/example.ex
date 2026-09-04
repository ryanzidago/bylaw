defmodule Bylaw.Contract.Example do
  @moduledoc false

  @type audience :: :admin | :member | {:guest, non_neg_integer()}
  @type style :: :short | :long

  @spec greeting(audience :: audience(), style :: style()) :: String.t()
  def greeting(:admin, :short), do: "Welcome, admin"
  def greeting(:member, :short), do: "Welcome back"
  def greeting({:guest, number}, :long), do: "Welcome, guest number #{number}"
end

defmodule Bylaw.Contract.Example.Bounded do
  @moduledoc false

  @spec choose(value :: value) :: value when value: :left | :right
  def choose(value), do: value
end

defmodule Bylaw.Contract.Example.Registration do
  @moduledoc false

  @type underage :: 0..17
  @type adult_age :: 18..120
  @type registration_age :: underage() | adult_age()

  @spec register(age :: registration_age()) :: :denied | :allowed
  def register(age) when age < 18, do: :denied
  def register(_), do: :allowed
end

defmodule Bylaw.Contract.Example.Partitions do
  @moduledoc false

  @opaque token :: integer()

  @spec integer_shape(value :: integer()) :: integer()
  def integer_shape(value), do: value

  @spec list_shape(value :: list(integer())) :: list(integer())
  def list_shape(value), do: value

  @spec binary_shape(value :: binary()) :: binary()
  def binary_shape(value), do: value

  @spec boolean_shape(value :: boolean()) :: boolean()
  def boolean_shape(value), do: value

  @spec nullable_shape(value :: integer() | nil) :: integer() | nil
  def nullable_shape(value), do: value

  @spec short_range(value :: 1..2) :: 1..2
  def short_range(value), do: value

  @spec opaque_shape(value :: token()) :: token()
  def opaque_shape(value), do: value
end
