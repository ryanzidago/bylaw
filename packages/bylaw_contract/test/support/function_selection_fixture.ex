defmodule Bylaw.Contract.TestFixtures.FunctionSelection do
  @moduledoc false

  @doc false
  @spec choose(1..3) :: :one | :other
  def choose(1), do: :one
  def choose(_), do: :other

  @doc false
  @spec unrelated(Bylaw.Contract.TestFixtures.SelectionUnloaded.value()) :: :unused
  def unrelated(_), do: :unused
end

defmodule Bylaw.Contract.TestFixtures.SelectionDefaults do
  @moduledoc false

  @doc false
  @spec defaulted(term(), atom()) :: {atom(), term()}
  def defaulted(value, style \\ :brief), do: {style, value}
end

defmodule Bylaw.Contract.TestFixtures.SelectionUnloaded do
  @moduledoc false

  @doc false
  @type value :: integer()

  @spec unused() :: :unused
  def unused, do: :unused
end
