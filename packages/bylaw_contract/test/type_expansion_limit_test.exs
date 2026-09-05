defmodule Bylaw.Contract.TypeExpansionLimitTest do
  use ExUnit.Case

  alias Bylaw.Contract.TypeExpansion
  alias Bylaw.Contract.TypeMatcher

  test "bounds alias resolution before creating an oversized graph" do
    calls = :counters.new(1, [])
    children = Enum.map(1..4100, &{:user_type, 0, :leaf, [{:integer, 0, &1}]})

    resolve = fn _module, :leaf, [_argument] ->
      :counters.add(calls, 1, 1)
      {:ok, {:type, 0, :integer, []}}
    end

    type = TypeExpansion.expand({:type, 0, :tuple, children}, __MODULE__, resolve)
    assert :counters.get(calls, 1) == 4096
    assert type == {:unsupported, {:type_expansion_limit, 4096}}
    refute TypeMatcher.supported?(type)
    assert TypeMatcher.match({}, type) == :unknown
  end
end
