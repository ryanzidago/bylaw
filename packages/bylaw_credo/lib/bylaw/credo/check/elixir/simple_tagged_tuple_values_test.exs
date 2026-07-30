defmodule Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValuesTest do
  use Credo.Test.Case
  use ExUnitProperties

  test "allows a variable as an ok tuple value" do
  end

  test "allows scalar literals as tagged tuple values" do
  end

  test "allows variables in every value position of a reply tuple" do
  end

  test "allows a tagged tuple containing another tagged tuple whose leaf value is a variable" do
  end

  test "allows recursively nested tagged tuples whose leaf values are scalar literals" do
  end

  test "reports a map constructed inside an ok tuple" do
  end

  test "reports the comparison summary map constructed inside an ok tuple" do
  end

  test "reports a map constructed inside an ok tuple nested beneath a cont tuple" do
  end

  test "reports the commit accumulator map inside an ok tuple nested beneath a cont tuple" do
  end

  test "reports a function call several tagged tuple levels beneath the outer return tuple" do
  end

  test "reports a struct constructed inside an ok tuple" do
  end

  test "reports a list constructed inside an ok tuple" do
  end

  test "reports an untagged tuple nested inside a tagged tuple" do
  end

  test "reports field access inside an ok tuple" do
  end

  test "reports a function call inside an ok tuple" do
  end

  test "reports a pipeline inside an ok tuple" do
  end

  test "reports string interpolation inside an ok tuple" do
  end

  test "reports an operator expression inside an ok tuple" do
  end

  test "reports a complex value in any position of a reply tuple" do
  end

  property "allows recursively nested tagged tuples when every generated leaf is a scalar literal or variable" do
  end

  property "reports recursively nested tagged tuples when any generated leaf is a complex expression" do
  end
end
