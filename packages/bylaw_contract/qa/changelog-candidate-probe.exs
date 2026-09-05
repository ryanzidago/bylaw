# Copy into the pinned upstream test directory; run with candidate-capture.exs.
defmodule BylawCandidateProbeTest do
  use ExUnit.Case, async: false
  import Mock
  alias Changelog.Github.{Client, Issuer, Pusher}

  test "declared GitHub alternatives through a mocked client" do
    source = %{org: "thechangelog", repo: "transcripts", name: "fixture", path: "fixture.md"}

    with_mock Client,
      file_exists?: fn _ -> false end,
      create_file: fn _, _, _ -> {:ok, %{status_code: 201}} end,
      create_issue: fn _, _, _ -> {:ok, %{status_code: 201}} end do
      assert {:ok, _} = Pusher.push(source, "")
      assert {:ok, _} = Issuer.create(source, "")
    end
  end
end
