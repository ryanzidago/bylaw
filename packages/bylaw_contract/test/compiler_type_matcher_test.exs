defmodule Bylaw.Contract.CompilerTypeMatcherTest do
  use ExUnit.Case

  alias Bylaw.Contract.CompilerTypeMatcher

  test "matches compiler literals and tuple shapes" do
    type = {:{}, [], [{:__block__, [], [:error]}, {:__block__, [], [:rejected]}]}

    assert CompilerTypeMatcher.supported?(type)
    assert CompilerTypeMatcher.match({:error, :rejected}, type) == :match
    assert CompilerTypeMatcher.match({:error, :other}, type) == :no_match
    assert CompilerTypeMatcher.match(:error, type) == :no_match
  end

  test "matches compiler boolean combinations" do
    integer = {:integer, [], []}
    zero = {:__block__, [], [0]}
    nonzero_integer = {:and, [], [integer, {:not, [], [zero]}]}

    assert CompilerTypeMatcher.supported?(nonzero_integer)
    assert CompilerTypeMatcher.match(1, nonzero_integer) == :match
    assert CompilerTypeMatcher.match(0, nonzero_integer) == :no_match
    assert CompilerTypeMatcher.match(1.0, nonzero_integer) == :no_match
  end

  test "matches proper and improper compiler list shapes" do
    integer = {:integer, [], []}
    proper = {:non_empty_list, [], [integer]}
    improper = {:non_empty_list, [], [integer, {:atom, [], []}]}

    assert CompilerTypeMatcher.match([1, 2], proper) == :match
    assert CompilerTypeMatcher.match([1 | :done], proper) == :no_match
    assert CompilerTypeMatcher.match([1, 2 | :done], improper) == :match
    assert CompilerTypeMatcher.match([1, 2 | 3], improper) == :no_match
  end

  test "keeps unknown compiler descriptor shapes explicit" do
    unknown = {:remote, [], [String, :t, []]}

    refute CompilerTypeMatcher.supported?(unknown)
    assert CompilerTypeMatcher.match("value", unknown) == :unknown
  end

  test "matches compiler module literals" do
    type = {:__aliases__, [], [:Bylaw, :Contract]}

    assert CompilerTypeMatcher.supported?(type)
    assert CompilerTypeMatcher.match(Bylaw.Contract, type) == :match
    assert CompilerTypeMatcher.match(Bylaw.Contract.Tracer, type) == :no_match
  end

  test "matches compiler struct and open map shapes" do
    struct_type =
      {:%, [],
       [
         {:__aliases__, [], [:URI]},
         {:%{}, [],
          [
            {{:__block__, [format: :keyword], [:scheme]}, {:binary, [], []}},
            {{:__block__, [format: :keyword], [:port]}, {:integer, [], []}}
          ]}
       ]}

    map_type =
      {:%{}, [],
       [
         {:..., [], nil},
         {{:__block__, [format: :keyword], [:status]}, {:__block__, [], [:ready]}}
       ]}

    assert CompilerTypeMatcher.supported?(struct_type)
    assert CompilerTypeMatcher.match(%URI{scheme: "https", port: 443}, struct_type) == :match
    assert CompilerTypeMatcher.match(%URI{scheme: "https", port: nil}, struct_type) == :no_match
    assert CompilerTypeMatcher.match(%{scheme: "https", port: 443}, struct_type) == :no_match

    assert CompilerTypeMatcher.supported?(map_type)
    assert CompilerTypeMatcher.match(%{status: :ready, extra: true}, map_type) == :match
    assert CompilerTypeMatcher.match(%{status: :waiting}, map_type) == :no_match
    assert CompilerTypeMatcher.match(%{}, map_type) == :no_match
  end

  test "requires exact keys for closed compiler map shapes" do
    type =
      {:%{}, [],
       [
         {{:__block__, [format: :keyword], [:status]}, {:__block__, [], [:ready]}}
       ]}

    assert CompilerTypeMatcher.supported?(type)
    assert CompilerTypeMatcher.match(%{status: :ready}, type) == :match
    assert CompilerTypeMatcher.match(%{status: :ready, extra: true}, type) == :no_match
    assert CompilerTypeMatcher.match(%{}, type) == :no_match
  end

  test "matches compiler function shapes by arity" do
    type =
      {:__block__, [],
       [
         [
           {:->, [], [[{:term, [], []}, {:term, [], []}], {:term, [], []}]}
         ]
       ]}

    assert CompilerTypeMatcher.supported?(type)
    assert CompilerTypeMatcher.match(fn _, _ -> :ok end, type) == :match
    assert CompilerTypeMatcher.match(fn _ -> :ok end, type) == :no_match
    assert CompilerTypeMatcher.match(:not_a_function, type) == :no_match
  end

  test "keeps unconstrained dynamic compiler types unsupported" do
    type = {:dynamic, [], []}

    refute CompilerTypeMatcher.supported?(type)
    assert CompilerTypeMatcher.match(:anything, type) == :unknown
  end

  test "matches compiler booleans and proper lists" do
    boolean = {:boolean, [], []}
    list = {:list, [], [{:boolean, [], []}]}

    assert CompilerTypeMatcher.supported?(boolean)
    assert CompilerTypeMatcher.match(true, boolean) == :match
    assert CompilerTypeMatcher.match(:ready, boolean) == :no_match

    assert CompilerTypeMatcher.supported?(list)
    assert CompilerTypeMatcher.match([], list) == :match
    assert CompilerTypeMatcher.match([true, false], list) == :match
    assert CompilerTypeMatcher.match([true | :done], list) == :no_match
    assert CompilerTypeMatcher.match([true, :ready], list) == :no_match
  end
end
