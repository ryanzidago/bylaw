defmodule Bylaw.Ecto.Query.RootWherePredicatesNormalizationPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Ecto.Query

  alias Bylaw.Ecto.Query.RootWherePredicates

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:sequence, :integer)
      field(:status, Ecto.Enum, values: [:draft, :published, :archived])
    end
  end

  property "integer in predicates remove nil values then sort and deduplicate candidates" do
    check all(values <- list_of(one_of([integer(), constant(nil)]), max_length: 20)) do
      query = from(post in Post, where: post.sequence in ^values)
      expected = values |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort()

      assert RootWherePredicates.branches(query, Post) == [
               [%{field: :sequence, operator: :in, values: expected}]
             ]
    end
  end

  property "permuting and duplicating integer in candidates preserves the extracted predicate" do
    check all(values <- list_of(one_of([integer(), constant(nil)]), max_length: 20)) do
      original = from(post in Post, where: post.sequence in ^values)
      transformed_values = Enum.reverse(values) ++ values
      transformed = from(post in Post, where: post.sequence in ^transformed_values)

      assert RootWherePredicates.branches(transformed, Post) ==
               RootWherePredicates.branches(original, Post)
    end
  end

  property "in predicates containing only nil values retain an empty candidate list" do
    check all(values <- nonempty(list_of(constant(nil), max_length: 20))) do
      query = from(post in Post, where: post.sequence in ^values)

      assert RootWherePredicates.branches(query, Post) == [
               [%{field: :sequence, operator: :in, values: []}]
             ]
    end
  end

  property "valid enum atoms and strings normalize to the same enum candidates" do
    check all(values <- list_of(member_of([:draft, :published, :archived]), max_length: 20)) do
      atom_query = from(post in Post, where: post.status in ^values)
      string_values = Enum.map(values, &Atom.to_string/1)
      string_query = from(post in Post, where: post.status in ^string_values)

      assert RootWherePredicates.branches(string_query, Post) ==
               RootWherePredicates.branches(atom_query, Post)
    end
  end

  property "root equality predicates are extracted with the field on either side" do
    check all(value <- integer()) do
      field_first = from(post in Post, where: post.sequence == ^value)
      value_first = from(post in Post, where: ^value == post.sequence)

      assert RootWherePredicates.branches(value_first, Post) ==
               RootWherePredicates.branches(field_first, Post)
    end
  end
end
