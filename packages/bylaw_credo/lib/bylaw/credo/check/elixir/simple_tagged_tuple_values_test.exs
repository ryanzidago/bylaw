defmodule Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValuesTest do
  use Credo.Test.Case
  use ExUnitProperties

  test "allows a variable as an ok tuple value" do
  end

  test "allows scalar literals as tagged tuple values" do
  end

  test "allows variables in every value position of a reply tuple" do
  end

  test "reports a map constructed inside an ok tuple" do
  end

  test "reports the comparison summary map constructed inside an ok tuple" do
  end

  test "reports a struct constructed inside an ok tuple" do
  end

  test "reports a list constructed inside an ok tuple" do
  end

  test "reports a nested tuple constructed inside an ok tuple" do
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

  property "allows tagged tuples when every generated value is a scalar literal or variable" do
  end

  property "reports tagged tuples when any generated value is a complex expression" do
  end
end
