defmodule Bylaw.Contract.ImproperListAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.{ImproperListFixture, TypeMatcher}

  test "proper-list types reject improper tails without raising" do
    integer = {:type, 0, :integer, []}

    types = [
      {:type, 0, :list, []},
      {:type, 0, :list, [integer]},
      {:type, 0, :nonempty_list, [integer]},
      {:bylaw_contract, :list_length, :multiple, integer},
      {:type, 0, :list, [{:unsupported, :fixture}]}
    ]

    for type <- types, tail <- [:tail, <<1>>, 5], prefix <- [[1], [1, 2, 3]] do
      assert TypeMatcher.match(prefix ++ tail, type) == :no_match
    end

    assert TypeMatcher.match([1, 2], {:type, 0, :list, [integer]}) == :match
    assert TypeMatcher.match([], {:type, 0, :list, [integer]}) == :match
    assert TypeMatcher.match([], {:type, 0, :nonempty_list, [integer]}) == :no_match
    assert TypeMatcher.match([1], {:type, 0, :list, [{:unsupported, :fixture}]}) == :unknown
  end

  test "character-list types reject improper tails without raising" do
    for name <- [:charlist, :string, :nonempty_charlist, :nonempty_string] do
      assert TypeMatcher.match([65, 66 | :tail], {:type, 0, name, []}) == :no_match
      assert TypeMatcher.match([65, 66], {:type, 0, name, []}) == :match
    end
  end

  test "valid improper iodata and unconstrained terms retain their matches" do
    for name <- [:iolist, :iodata, :any, :term] do
      assert TypeMatcher.match([65 | <<66>>], {:type, 0, name, []}) == :match
    end

    for name <- [:iolist, :iodata] do
      assert TypeMatcher.match([65 | :tail], {:type, 0, name, []}) == :no_match
    end
  end

  test "observing improper arguments and returns preserves callers and completes coverage" do
    {:ok, observer} = Contract.start([ImproperListFixture], checks: [Contract.Check.Typespec])
    value = [1, 2 | :tail]
    assert ImproperListFixture.echo(value) == value
    coverage = Contract.stop(observer)
    assert Map.get(coverage, :status, :complete) == :complete
    mfa = {ImproperListFixture, :echo, 1}
    assert coverage.calls[mfa] == 1
    assert coverage.return_events[mfa] == 1

    assert Enum.all?(
             coverage.input_classes ++ coverage.return_alternatives,
             &(Map.get(coverage.hits, &1.id, 0) == 0)
           )
  end
end
