defmodule Bylaw.Contract.FalseyNonemptyListFixture do
  @moduledoc false

  @doc false
  @spec terms(nonempty_list(term())) :: nonempty_list(term()) | :unused
  def terms(value), do: value

  @doc false
  @spec booleans(nonempty_list(boolean())) :: nonempty_list(boolean()) | :unused
  def booleans(value), do: value
end
