defmodule Bylaw.Ecto.Query.RootWherePredicatesRejectionPropertyTest do
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

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:sequence, :integer)
    end
  end

  property "an invalid integer candidate rejects the entire in predicate" do
    check all(
            values <- list_of(integer(), max_length: 20),
            invalid <- one_of([binary(), boolean()])
          ) do
      query = from(post in Post, where: post.sequence in ^[invalid | values])

      assert RootWherePredicates.branches(query, Post) == [[]]
    end
  end

  property "an invalid enum candidate rejects the entire in predicate" do
    check all(
            values <- list_of(member_of([:draft, :published, :archived]), max_length: 20),
            invalid <- member_of([:pending, :removed, "unknown"])
          ) do
      query = from(post in Post, where: post.status in ^[invalid | values])

      assert RootWherePredicates.branches(query, Post) == [[]]
    end
  end

  property "unsupported equality values do not produce root predicates" do
    check all(value <- one_of([binary(), boolean(), list_of(integer(), max_length: 4)])) do
      query = from(post in Post, where: post.sequence == ^value)

      assert RootWherePredicates.branches(query, Post) == [[]]
    end
  end

  property "predicates on non-root bindings do not produce root predicates" do
    check all(value <- integer()) do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: comment.sequence == ^value
        )

      assert RootWherePredicates.branches(query, Post) == [[]]
    end
  end
end
