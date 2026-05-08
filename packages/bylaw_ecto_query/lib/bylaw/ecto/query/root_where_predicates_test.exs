defmodule Bylaw.Ecto.Query.RootWherePredicatesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.RootWherePredicates

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:active, :boolean)
      field(:published_at, :utc_datetime)
      field(:sequence, :integer)
      field(:status, Ecto.Enum, values: [:draft, :published, :archived])
      field(:title, :string)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:status, Ecto.Enum, values: [:draft, :published, :archived])
    end
  end

  describe "branches/2" do
    test "returns one empty branch when there are no supported predicates" do
      query = from(post in Post)

      assert RootWherePredicates.branches(query, Post) == [[]]
      assert RootWherePredicates.branches(:not_a_query, Post) == [[]]
    end

    test "extracts root equality, in, and is_nil predicates" do
      values = [2, 1, nil, 1]

      query =
        from(post in Post,
          as: :post,
          where:
            field(as(:post), :status) == "draft" and
              post.sequence in ^values and
              is_nil(post.title)
        )

      assert RootWherePredicates.branches(query, Post) == [
               [
                 %{field: :status, operator: :==, values: [:draft]},
                 %{field: :sequence, operator: :in, values: [1, 2]},
                 %{field: :title, operator: :is_nil, values: [nil]}
               ]
             ]
    end

    test "extracts empty in predicates after removing nil candidate values" do
      query = from(post in Post, where: post.id in ^[nil])

      assert RootWherePredicates.branches(query, Post) == [
               [%{field: :id, operator: :in, values: []}]
             ]
    end

    test "splits or expressions and merges later and predicates into every branch" do
      query =
        from(post in Post,
          where: post.status == :draft,
          or_where: post.status == :published,
          where: post.sequence == 1
        )

      assert RootWherePredicates.branches(query, Post) == [
               [
                 %{field: :status, operator: :==, values: [:draft]},
                 %{field: :sequence, operator: :==, values: [1]}
               ],
               [
                 %{field: :status, operator: :==, values: [:published]},
                 %{field: :sequence, operator: :==, values: [1]}
               ]
             ]
    end

    test "ignores unsupported values, fragments, and non-root binding predicates" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: comment.status == :draft,
          where: post.status in ^["not-a-status"],
          where: fragment("? = ?", post.status, ^:draft),
          where: post.published_at == "2026-05-03T00:00:00Z",
          where: post.active == true
        )

      assert RootWherePredicates.branches(query, Post) == [
               [%{field: :active, operator: :==, values: [true]}]
             ]
    end
  end
end
