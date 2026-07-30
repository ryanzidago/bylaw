defmodule Bylaw.CheckRunnerPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Bylaw.CheckRunner

  defmodule Issue do
    defstruct [:message]
  end

  defmodule Check do
  end

  property "valid issue lists are returned unchanged" do
    check all(messages <- list_of(string(:alphanumeric, max_length: 40), min_length: 1)) do
      issues = Enum.map(messages, &%Issue{message: &1})

      assert CheckRunner.result!(Check, {:error, issues}, Issue, 3) == issues
    end
  end
end
