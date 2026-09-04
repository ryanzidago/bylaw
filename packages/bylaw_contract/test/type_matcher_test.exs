defmodule Bylaw.Contract.TypeMatcherTest do
  use ExUnit.Case

  alias Bylaw.Contract.Example

  test "matches common typespec shapes" do
    assert Bylaw.Contract.TypeMatcher.match(:admin, {:atom, 0, :admin}) == :match
    assert Bylaw.Contract.TypeMatcher.match(7, {:type, 0, :non_neg_integer, []}) == :match

    tuple_type =
      {:type, 0, :tuple, [{:atom, 0, :guest}, {:type, 0, :non_neg_integer, []}]}

    assert Bylaw.Contract.TypeMatcher.match({:guest, 7}, tuple_type) == :match
    assert Bylaw.Contract.TypeMatcher.match({:guest, -1}, tuple_type) == :no_match
    assert Bylaw.Contract.TypeMatcher.match(Example, {:type, 0, :module, []}) == :match

    assert Bylaw.Contract.TypeMatcher.match({Bylaw.Contract, :start, 1}, {:type, 0, :mfa, []}) ==
             :match

    assert Bylaw.Contract.TypeMatcher.match(["nested", 0], {:type, 0, :iolist, []}) == :match

    required_binary_map =
      {:type, 0, :map,
       [
         {:type, 0, :map_field_exact, [{:type, 0, :binary, []}, {:type, 0, :binary, []}]}
       ]}

    assert Bylaw.Contract.TypeMatcher.match(%{"key" => "value"}, required_binary_map) == :match
    assert Bylaw.Contract.TypeMatcher.match(%{}, required_binary_map) == :no_match

    optional_atom_map =
      {:type, 0, :map,
       [
         {:type, 0, :map_field_assoc, [{:type, 0, :atom, []}, {:type, 0, :any, []}]}
       ]}

    assert Bylaw.Contract.TypeMatcher.match(%URI{}, optional_atom_map) == :match
  end
end
