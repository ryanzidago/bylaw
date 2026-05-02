defmodule Bylaw.Ecto.Query.Checks.CartesianJoinsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.CartesianJoins
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)

      has_many(:comments, Bylaw.Ecto.Query.Checks.CartesianJoinsTest.Comment)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:body, :string)

      belongs_to(:post, Bylaw.Ecto.Query.Checks.CartesianJoinsTest.Post)
    end
  end

  describe "validate/3" do
    test "returns an issue when a join uses a literal true on expression" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{} = issue} = CartesianJoins.validate(:all, query, [])

      assert issue.check == CartesianJoins
      assert issue.meta.operation == :all
      assert issue.meta.join_index == 0
      assert issue.meta.binding_index == 1
      assert issue.meta.join_qual == :inner
      assert issue.meta.reason == :literal_true_on

      assert issue.message ==
               "expected join 0 not to be cartesian; found a literal true on expression"
    end

    test "returns an issue when a left join uses a literal true on expression" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{} = issue} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :left
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when a query uses cross_join" do
      query =
        from(post in Post,
          cross_join: comment in Comment,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{} = issue} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :cross
      assert issue.meta.reason == :cross_join

      assert issue.message ==
               "expected join 0 not to be cartesian; found cross_join"
    end

    test "returns an issue when a query uses cross_lateral_join" do
      comment_ids =
        from(comment in Comment,
          where: comment.post_id == parent_as(:post).id,
          select: comment.id
        )

      query =
        from(post in Post,
          as: :post,
          cross_lateral_join: comment_id in subquery(comment_ids),
          select: {post.id, comment_id.id}
        )

      assert {:error, %Issue{} = issue} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :cross_lateral
      assert issue.meta.reason == :cross_lateral_join

      assert issue.message ==
               "expected join 0 not to be cartesian; found cross_lateral_join"
    end

    test "returns all issues when several joins are cartesian" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          cross_join: other_comment in Comment,
          select: {post.id, comment.id, other_comment.id}
        )

      assert {:error, [%Issue{} = first, %Issue{} = second]} =
               CartesianJoins.validate(:all, query, [])

      assert first.meta.join_index == 0
      assert first.meta.reason == :literal_true_on
      assert second.meta.join_index == 1
      assert second.meta.reason == :cross_join
    end

    test "passes when joins have restricting on predicates" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes association joins whose association predicate is represented separately" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes for every Ecto prepare_query operation when joins are constrained" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok = CartesianJoins.validate(operation, query, [])
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when a join is cartesian" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} = CartesianJoins.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.reason == :literal_true_on
      end)
    end

    test "respects the explicit query-level escape hatch" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, cartesian_joins: [validate: false])
    end

    test "requires an explicit false escape hatch" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{}} =
               CartesianJoins.validate(:all, query, cartesian_joins: [validate: nil])
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown :cartesian_joins option: :allow", fn ->
        CartesianJoins.validate(:all, query, cartesian_joins: [allow: true])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :cartesian_joins opts to be a keyword list, got: :bad",
                   fn ->
                     CartesianJoins.validate(:all, query, cartesian_joins: :bad)
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:bad]", fn ->
        CartesianJoins.validate(:all, query, [:bad])
      end
    end
  end
end
