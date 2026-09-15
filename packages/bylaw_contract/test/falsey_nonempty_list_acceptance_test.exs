defmodule Bylaw.Contract.FalseyNonemptyListAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.{FalseyNonemptyListFixture, TypeMatcher}

  test "nonempty term lists match a single false" do
    assert TypeMatcher.match([false], {:type, 0, :nonempty_list, [{:type, 0, :term, []}]}) ==
             :match
  end

  test "nonempty term lists match a single nil" do
    assert TypeMatcher.match([nil], {:type, 0, :nonempty_list, [{:type, 0, :term, []}]}) ==
             :match
  end

  test "nonempty term lists match false and nil together" do
    assert TypeMatcher.match([false, nil], {:type, 0, :nonempty_list, [{:type, 0, :term, []}]}) ==
             :match
  end

  test "nonempty boolean lists match false values and reject nonboolean elements" do
    type = {:type, 0, :nonempty_list, [{:type, 0, :boolean, []}]}

    for value <- [[false], [false, false], [true], [false, true], [true, false]] do
      assert TypeMatcher.match(value, type) == :match
    end

    for value <- [[nil], [false, nil], [nil, false], [false, 0], [true, nil]] do
      assert TypeMatcher.match(value, type) == :no_match
    end
  end

  test "nonempty list types reject empty lists and nonlists" do
    for element <- [{:type, 0, :term, []}, {:type, 0, :boolean, []}, {:unsupported, :fixture}],
        value <- [[], false, nil, :atom, 0, %{}, <<>>, {}] do
      assert TypeMatcher.match(value, {:type, 0, :nonempty_list, [element]}) == :no_match
    end
  end

  test "nonempty falsey lists preserve unknown element results" do
    unsupported = {:unsupported, :fixture}
    partial = {:type, 0, :union, [{:atom, 0, false}, unsupported]}

    for value <- [[false], [nil], [false, nil]] do
      assert TypeMatcher.match(value, {:type, 0, :nonempty_list, [unsupported]}) == :unknown
    end

    assert TypeMatcher.match([false], {:type, 0, :nonempty_list, [partial]}) == :match

    for value <- [[false, nil], [nil, false]] do
      assert TypeMatcher.match(value, {:type, 0, :nonempty_list, [partial]}) == :unknown
    end
  end

  test "nonempty lists preserve no_match precedence over unknown elements in either order" do
    element = {:type, 0, :tuple, [{:type, 0, :boolean, []}, {:unsupported, :fixture}]}
    type = {:type, 0, :nonempty_list, [element]}

    assert TypeMatcher.match([{false, nil}], type) == :unknown

    for value <- [[{false, nil}, {nil, nil}], [{nil, nil}, {false, nil}]] do
      assert TypeMatcher.match(value, type) == :no_match
    end
  end

  test "nonempty falsey lists reject improper tails even with unsupported elements" do
    for element <- [{:type, 0, :term, []}, {:type, 0, :boolean, []}, {:unsupported, :fixture}],
        prefix <- [[false], [nil], [false, nil]],
        tail <- [false, nil, :tail, <<1>>, 5] do
      assert TypeMatcher.match(prefix ++ tail, {:type, 0, :nonempty_list, [element]}) == :no_match
    end
  end

  test "observing falsey nonempty arguments and returns records exact typespec hits" do
    {:ok, observer} =
      Contract.start([FalseyNonemptyListFixture], checks: [Contract.Check.Typespec])

    try do
      for value <- [[false], [nil], [false, nil]] do
        assert FalseyNonemptyListFixture.terms(value) === value
      end

      for value <- [[false], [false, false]] do
        assert FalseyNonemptyListFixture.booleans(value) === value
      end

      coverage = Contract.stop(observer)
      assert Map.get(coverage, :status, :complete) == :complete
      refute Map.has_key?(coverage, :incomplete)

      for {function, count} <- [terms: 3, booleans: 2] do
        mfa = {FalseyNonemptyListFixture, function, 1}
        assert coverage.calls[mfa] == count
        assert coverage.return_events[mfa] == count
        inputs = Enum.filter(coverage.input_classes, &(&1.function == function))
        assert Enum.count(inputs) == 2
        assert Enum.all?(inputs, & &1.supported?)

        assert Map.new(inputs, &{&1.partition, Map.get(coverage.hits, &1.id, 0)}) == %{
                 singleton: count - 1,
                 multiple: 1
               }

        returns = Enum.filter(coverage.return_alternatives, &(&1.function == function))
        assert Enum.count(returns) == 2
        assert Enum.all?(returns, & &1.supported?)
        [unused] = Enum.filter(returns, &(&1.label == ":unused"))
        [matched] = Enum.reject(returns, &(&1.label == ":unused"))
        assert Map.get(coverage.hits, unused.id, 0) == 0
        assert Map.get(coverage.hits, matched.id, 0) == count
      end
    after
      if Process.alive?(observer), do: Contract.stop(observer)
    end
  end
end
