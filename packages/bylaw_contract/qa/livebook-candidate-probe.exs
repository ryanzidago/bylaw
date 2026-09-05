# Copy into the pinned upstream test directory; run with candidate-capture.exs.
defmodule BylawCandidateProbeTest do
  use ExUnit.Case, async: false

  test "utils input and return boundaries" do
    assert Livebook.Utils.node_from_id("") == :error
    assert Livebook.Utils.apply_rewind("") == ""
    assert Livebook.Utils.keyword_deep_merge([a: 1, b: 2], c: 3, d: 4) == [a: 1, b: 2, c: 3, d: 4]
  end
end
