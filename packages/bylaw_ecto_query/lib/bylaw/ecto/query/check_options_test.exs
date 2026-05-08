defmodule Bylaw.Ecto.Query.CheckOptionsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Ecto.Query.CheckOptions

  describe "keyword_list!/2" do
    test "returns keyword lists" do
      assert CheckOptions.keyword_list!([validate: true], "opts") == [validate: true]
    end

    test "raises for non-keyword lists" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        CheckOptions.keyword_list!([:invalid], "opts")
      end
    end

    test "raises for non-lists" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        CheckOptions.keyword_list!(:invalid, "opts")
      end
    end
  end

  describe "normalize!/2" do
    test "returns check-specific options" do
      assert CheckOptions.normalize!([validate: false], [:validate]) == [validate: false]
    end

    test "raises when options are not a keyword list" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        CheckOptions.normalize!([:invalid], [:validate])
      end
    end

    test "raises when options are not a list" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        CheckOptions.normalize!(:invalid, [:validate])
      end
    end

    test "raises when check options contain unsupported keys" do
      assert_raise ArgumentError, "unknown option: :fields", fn ->
        CheckOptions.normalize!([fields: [:status]], [:validate])
      end
    end

    test "preserves loose validation when allowed keys are unrestricted" do
      assert CheckOptions.normalize!([fields: [:status]], :any) == [fields: [:status]]
    end
  end

  describe "enabled?/1" do
    test "only explicit false disables a check" do
      assert CheckOptions.enabled?([])
      assert CheckOptions.enabled?(validate: true)
      assert CheckOptions.enabled?(validate: nil)
      refute CheckOptions.enabled?(validate: false)
    end
  end

  describe "match!/1" do
    test "defaults to any" do
      assert CheckOptions.match!([]) == :any
    end

    test "accepts any and all" do
      assert CheckOptions.match!(match: :any) == :any
      assert CheckOptions.match!(match: :all) == :all
    end

    test "raises for unsupported match values" do
      assert_raise ArgumentError, "expected :match to be :any or :all, got: :one", fn ->
        CheckOptions.match!(match: :one)
      end
    end
  end

  describe "fetch_non_empty_atoms!/2" do
    test "returns configured atoms" do
      assert CheckOptions.fetch_non_empty_atoms!([keys: [:organisation_id]], :keys) == [
               :organisation_id
             ]
    end

    test "raises when the key is missing" do
      assert_raise ArgumentError, "missing required :keys option", fn ->
        CheckOptions.fetch_non_empty_atoms!([], :keys)
      end
    end

    test "raises when the value is empty" do
      assert_raise ArgumentError, "expected :keys to be a non-empty list of atoms, got: []", fn ->
        CheckOptions.fetch_non_empty_atoms!([keys: []], :keys)
      end
    end

    test "raises when the value is not a list" do
      assert_raise ArgumentError,
                   "expected :keys to be a non-empty list of atoms, got: :organisation_id",
                   fn ->
                     CheckOptions.fetch_non_empty_atoms!([keys: :organisation_id], :keys)
                   end
    end

    test "raises when the list contains non-atoms" do
      assert_raise ArgumentError,
                   ~s(expected :keys to contain only atoms, got: "organisation_id"),
                   fn ->
                     CheckOptions.fetch_non_empty_atoms!([keys: ["organisation_id"]], :keys)
                   end
    end
  end
end
