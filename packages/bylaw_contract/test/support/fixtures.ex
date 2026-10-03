defmodule Bylaw.Contract.Fixtures.Greeter do
  @moduledoc false

  @type audience :: :admin | :member | {:guest, non_neg_integer()}

  @doc false
  @spec greet(audience()) :: String.t()
  def greet(:admin), do: "admin"
  def greet(:member), do: "member"
  def greet({:guest, _id}), do: "guest"
end

defmodule Bylaw.Contract.Fixtures.Ages do
  @moduledoc false

  @doc false
  @spec bucket(0..17 | 18..120) :: :minor | :adult
  def bucket(age) when age < 18, do: :minor
  def bucket(age) when age >= 18 and age <= 120, do: :adult
end

defmodule Bylaw.Contract.Fixtures.Kinds do
  @moduledoc false

  @doc false
  def kind(value) when is_integer(value) and value > 0, do: :positive
  def kind(value) when is_integer(value) or is_float(value), do: :number
  def kind(_value), do: :other
end

defmodule Bylaw.Contract.Fixtures.Heads do
  @moduledoc false

  @doc false
  def first(list) when hd(list) == 1, do: :one
  def first(_list), do: :other
end

defmodule Bylaw.Contract.Fixtures.Plain do
  @moduledoc false

  @doc false
  def single(value), do: helper(value)

  @doc false
  def with_default(left, right \\ 1), do: left + right

  defp helper(value) when is_integer(value), do: value
  defp helper(_value), do: 0
end

defmodule Bylaw.Contract.Fixtures.Raiser do
  @moduledoc false

  @doc false
  def run(:ok), do: :ok
  def run(:raise), do: raise(ArgumentError, "fixture raise")
  def run(:throw), do: throw(:fixture_throw)
  def run(:exit), do: exit(:fixture_exit)
end

defmodule Bylaw.Contract.Fixtures.Countdown do
  @moduledoc false

  @doc false
  @spec count_down(non_neg_integer()) :: :done | :never
  def count_down(0), do: :done
  def count_down(count), do: count_down(count - 1)
end

defmodule Bylaw.Contract.Fixtures.Opaque do
  @moduledoc false

  @opaque token :: binary()

  @doc false
  @spec token(boolean()) :: :ok | token()
  def token(true), do: :ok
  def token(false), do: "opaque token"
end

defmodule Bylaw.Contract.Fixtures.Generated do
  @moduledoc false

  for {name, value} <- [one: 1, two: 2] do
    @doc false
    @spec unquote(name)(:a | :b) :: pos_integer() | non_neg_integer()
    def unquote(name)(:a), do: unquote(value)
    def unquote(name)(:b), do: unquote(value) + 1
  end
end

defmodule Bylaw.Contract.Fixtures.Table do
  @moduledoc false

  for {prefix, label} <- [{"10.", :private}, {"192.", :lan}] do
    def classify(unquote(prefix) <> _rest = address) when byte_size(address) > 4,
      do: unquote(label)
  end

  def classify(_address), do: :public
end

defmodule Bylaw.Contract.Fixtures.Shapes do
  @moduledoc false

  @spec describe(String.t(), list(integer()), integer(), boolean()) :: :ok
  def describe(_name, _items, _count, _flag), do: :ok
end

defmodule Bylaw.Contract.Fixtures.Fallthrough do
  @moduledoc false

  @spec route(atom(), integer()) :: atom()
  def route(:pending, count) when count > 0, do: :queued
  def route(:done, count) when is_integer(count), do: :finished
  def route(:retry, count) when count > 0, do: :again
  def route(:retry, _count), do: :gave_up
  def route(:failed, _count), do: :failed
end
