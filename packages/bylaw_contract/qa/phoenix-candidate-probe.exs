# Copy into the pinned upstream test directory; run with candidate-capture.exs.
defmodule BylawCandidateProbeTest do
  use ExUnit.Case, async: false

  test "token input boundaries" do
    key = String.duplicate("a", 64)
    token = Phoenix.Token.sign(key, "", 1, signed_at: 0, key_iterations: 1)
    assert is_binary(token)
    assert is_binary(Phoenix.Token.sign(key, "", 1, signed_at: 1, key_iterations: 1))
    assert Phoenix.Token.verify(key, "", "") == {:error, :invalid}
  end
end
