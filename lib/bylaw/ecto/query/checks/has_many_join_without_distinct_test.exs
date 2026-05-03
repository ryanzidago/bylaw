defmodule Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinct
  alias Bylaw.Ecto.Query.Issue

  @root_read_operations [:all, :stream]
  @non_root_returning_operations [:update_all, :delete_all, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)

      has_many(:comments, Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest.Comment)

      has_one(:latest_comment, Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest.Comment)

      many_to_many(:tags, Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest.Tag,
        join_through: "posts_tags"
      )
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:status, :string)

      belongs_to(:post, Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest.Post)
      belongs_to(:author, Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest.Author)

      has_many(:reactions, Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest.Reaction)
    end
  end

  defmodule Reaction do
    use Ecto.Schema

    schema "reactions" do
      field(:name, :string)

      belongs_to(:comment, Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest.Comment)
    end
  end

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field(:name, :string)

      has_many(:comments, Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinctTest.Comment)
    end
  end

  defmodule Tag do
    use Ecto.Schema

    schema "tags" do
      field(:name, :string)
    end
  end

  defmodule SchemaLessSource do
    use Ecto.Schema

    schema "schema_less_sources" do
      field(:title, :string)
    end
  end

  describe "validate/3" do
    test "returns an issue when an implicit root select joins a has_many association" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: comment.status == ^"published"
        )

      assert {:error, [%Issue{} = issue]} =
               HasManyJoinWithoutDistinct.validate(:all, query, [])

      assert issue.check == HasManyJoinWithoutDistinct

      assert issue.message ==
               "expected root-selecting query with many association join :comments to include distinct or group_by"

      assert issue.meta.operation == :all
      assert issue.meta.association == :comments
      assert issue.meta.join_index == 0
      assert issue.meta.binding_index == 1
      assert issue.meta.join_qual == :inner
      assert issue.meta.owner_binding_index == 0
      assert issue.meta.owner_schema == Post
      assert issue.meta.join_schema == Comment
    end

    test "returns an issue when an explicit root select joins a has_many association" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: comment.status == ^"published",
          select: post
        )

      assert {:error, [%Issue{} = issue]} =
               HasManyJoinWithoutDistinct.validate(:all, query, [])

      assert issue.meta.association == :comments
      assert issue.meta.owner_schema == Post
      assert issue.meta.join_schema == Comment
    end

    test "returns an issue when a root select joins a many_to_many association" do
      query =
        from(post in Post,
          join: tag in assoc(post, :tags),
          where: tag.name == ^"ecto"
        )

      assert {:error, [%Issue{} = issue]} =
               HasManyJoinWithoutDistinct.validate(:all, query, [])

      assert issue.meta.association == :tags
      assert issue.meta.owner_schema == Post
      assert issue.meta.join_schema == Tag
    end

    test "returns an issue when a left join can multiply root rows" do
      query =
        from(post in Post,
          left_join: comment in assoc(post, :comments),
          select: post
        )

      assert {:error, [%Issue{} = issue]} =
               HasManyJoinWithoutDistinct.validate(:all, query, [])

      assert issue.meta.association == :comments
      assert issue.meta.join_qual == :left
    end

    test "returns issues for direct nested many association joins in the main query" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          join: reaction in assoc(comment, :reactions),
          select: post
        )

      assert {:error, [%Issue{} = comment_issue, %Issue{} = reaction_issue]} =
               HasManyJoinWithoutDistinct.validate(:all, query, [])

      assert comment_issue.meta.association == :comments
      assert comment_issue.meta.owner_binding_index == 0
      assert comment_issue.meta.owner_schema == Post

      assert reaction_issue.meta.association == :reactions
      assert reaction_issue.meta.owner_binding_index == 1
      assert reaction_issue.meta.owner_schema == Comment
      assert reaction_issue.meta.join_schema == Reaction
    end

    test "uses explicit join schemas for later direct association joins" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: reaction in assoc(comment, :reactions),
          select: post
        )

      assert {:error, [%Issue{} = issue]} =
               HasManyJoinWithoutDistinct.validate(:all, query, [])

      assert issue.meta.association == :reactions
      assert issue.meta.owner_binding_index == 1
      assert issue.meta.owner_schema == Comment
      assert issue.meta.join_schema == Reaction
    end

    test "returns one issue per direct many association join" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          join: tag in assoc(post, :tags)
        )

      assert {:error, [%Issue{}, %Issue{}] = issues} =
               HasManyJoinWithoutDistinct.validate(:all, query, [])

      assert Enum.map(issues, & &1.meta.join_index) == [0, 1]
      assert Enum.map(issues, & &1.meta.association) == [:comments, :tags]
    end

    test "passes when the query uses distinct" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: comment.status == ^"published",
          distinct: post.id
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the query uses literal distinct" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: comment.status == ^"published",
          distinct: true
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the query uses group_by" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: comment.status == ^"published",
          group_by: post.id
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the query explicitly selects joined rows" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: comment.status == ^"published",
          select: {post, comment}
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the query explicitly selects root fields instead of root structs" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: comment.status == ^"published",
          select: post.id
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the query uses preload assembly" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: comment.status == ^"published",
          preload: [comments: comment]
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the association is has_one" do
      query =
        from(post in Post,
          join: comment in assoc(post, :latest_comment),
          where: comment.status == ^"published"
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the association is belongs_to" do
      query =
        from(comment in Comment,
          join: author in assoc(comment, :author),
          where: author.name == ^"Ada"
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when there are no joins" do
      query = from(post in Post)

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when a many join is manual instead of assoc/2" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the root source is schema-less" do
      query =
        from(post in "posts",
          join: comment in Comment,
          on: comment.post_id == field(post, :id),
          select: post
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok = HasManyJoinWithoutDistinct.validate(:all, :not_a_query, [])
    end

    test "passes malformed and unresolved raw join maps" do
      query = %{
        from: %{source: {"schema_less_sources", SchemaLessSource}},
        joins: [
          %{assoc: {0, :missing_association}, qual: :inner},
          %{assoc: {:invalid, :comments}, qual: :inner},
          :not_a_join
        ],
        select: nil,
        distinct: nil,
        group_bys: [],
        preloads: [],
        assocs: []
      }

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "does not inspect source subqueries" do
      posts_query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          select: post
        )

      query =
        from(post in subquery(posts_query),
          select: post
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "does not inspect join subqueries" do
      comments_query =
        from(comment in Comment,
          join: reaction in assoc(comment, :reactions),
          select: comment
        )

      query =
        from(post in Post,
          join: comment in subquery(comments_query),
          on: comment.post_id == post.id,
          select: post
        )

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "does not inspect CTE row sources" do
      cte_query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          select: post
        )

      query =
        Post
        |> with_cte("many_posts", as: ^cte_query)
        |> join(:inner, [post], joined_post in "many_posts", on: joined_post.id == post.id)
        |> select([post], post)

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "does not inspect set operation branches" do
      safe_query = from(post in Post, select: post)

      many_join_query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          select: post
        )

      query = union_all(safe_query, ^many_join_query)

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "does not inspect any query with set operations" do
      root_many_join_query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          select: post
        )

      safe_query = from(post in Post, select: post)
      query = union_all(root_many_join_query, ^safe_query)

      assert :ok = HasManyJoinWithoutDistinct.validate(:all, query, [])
    end

    test "returns an issue for root-row read operations" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments)
        )

      Enum.each(@root_read_operations, fn operation ->
        assert {:error, [%Issue{} = issue]} =
                 HasManyJoinWithoutDistinct.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.association == :comments
      end)
    end

    test "passes non-root-returning operations when a many join exists" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments)
        )

      Enum.each(@non_root_returning_operations, fn operation ->
        assert :ok = HasManyJoinWithoutDistinct.validate(operation, query, [])
      end)
    end

    test "skips validation when disabled" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments)
        )

      assert :ok =
               HasManyJoinWithoutDistinct.validate(:all, query, validate: false)
    end

    test "validates when validate is explicitly true" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments)
        )

      assert {:error, [%Issue{}]} =
               HasManyJoinWithoutDistinct.validate(:all, query, validate: true)
    end

    test "requires an explicit false escape hatch" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments)
        )

      assert {:error, [%Issue{}]} =
               HasManyJoinWithoutDistinct.validate(:all, query, validate: nil)
    end

    test "raises when opts are not a keyword list" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        HasManyJoinWithoutDistinct.validate(:all, from(post in Post), :invalid)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        HasManyJoinWithoutDistinct.validate(:all, from(post in Post), [:invalid])
      end
    end

    test "raises when opts contain unsupported keys" do
      assert_raise ArgumentError, "unknown option: :fields", fn ->
        HasManyJoinWithoutDistinct.validate(:all, from(post in Post), fields: [:comments])
      end
    end
  end
end
