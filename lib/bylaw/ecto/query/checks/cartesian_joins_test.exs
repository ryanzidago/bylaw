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
    test "passes when there are no joins" do
      query = from(post in Post)

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok = CartesianJoins.validate(:all, :not_a_query, [])
    end

    test "returns an issue when a join uses a literal true on expression" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.check == CartesianJoins
      assert issue.meta.operation == :all
      assert issue.meta.join_index == 0
      assert issue.meta.binding_index == 1
      assert issue.meta.join_qual == :inner
      assert issue.meta.reason == :literal_true_on

      assert issue.message ==
               "expected join 0 not to be cartesian; found a literal true on expression"
    end

    test "returns an issue when a schema-less join uses a literal true on expression" do
      query =
        from(post in "posts",
          join: comment in "comments",
          on: true,
          select: {field(post, :id), field(comment, :id)}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :inner
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when Ecto normalizes an interpolated true on expression" do
      always_join? = true

      query =
        from(post in Post,
          join: comment in Comment,
          on: ^always_join?,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :inner
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when a left join uses a literal true on expression" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :left
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when a right join uses a literal true on expression" do
      query =
        from(post in Post,
          right_join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :right
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when a full join uses a literal true on expression" do
      query =
        from(post in Post,
          full_join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :full
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when an uncorrelated inner lateral join uses a literal true on expression" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(uncorrelated_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :inner_lateral
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when an uncorrelated left lateral join uses a literal true on expression" do
      query =
        from(post in Post,
          as: :post,
          left_lateral_join: comment in subquery(uncorrelated_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :left_lateral
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when a query uses cross_join" do
      query =
        from(post in Post,
          cross_join: comment in Comment,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :cross
      assert issue.meta.reason == :cross_join

      assert issue.message ==
               "expected join 0 not to be cartesian; found cross_join"
    end

    test "returns an issue when a cross_join uses an association source" do
      query =
        from(post in Post,
          cross_join: comment in assoc(post, :comments),
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :cross
      assert issue.meta.reason == :cross_join
    end

    test "returns an issue when a query uses uncorrelated cross_lateral_join" do
      query =
        from(post in Post,
          as: :post,
          cross_lateral_join: comment_id in subquery(uncorrelated_comment_id_subquery()),
          select: {post.id, comment_id.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :cross_lateral
      assert issue.meta.reason == :cross_lateral_join

      assert issue.message ==
               "expected join 0 not to be cartesian; found cross_lateral_join"
    end

    test "returns an issue when an inner lateral join only projects a parent binding" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(parent_projecting_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :inner_lateral
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when a left lateral join only projects a parent binding" do
      query =
        from(post in Post,
          as: :post,
          left_lateral_join: comment in subquery(parent_projecting_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :left_lateral
      assert issue.meta.reason == :literal_true_on
    end

    test "returns an issue when a cross_lateral_join only projects a parent binding" do
      query =
        from(post in Post,
          as: :post,
          cross_lateral_join: comment_id in subquery(parent_projecting_comment_id_subquery()),
          select: {post.id, comment_id.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :cross_lateral
      assert issue.meta.reason == :cross_lateral_join
    end

    test "returns an issue when a lateral subquery only compares parent bindings" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(parent_comparing_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :inner_lateral
      assert issue.meta.reason == :literal_true_on
    end

    test "passes when a correlated inner lateral join uses a literal true on expression" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes when a correlated lateral subquery references a dynamic parent field" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(dynamic_parent_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes when a correlated lateral subquery references a dynamic local field" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(dynamic_local_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes when a correlated lateral subquery uses a named local binding" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(named_local_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes when the parent field is on the left side of the lateral predicate" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(parent_left_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "returns an issue when a lateral subquery references an unknown parent alias" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(unknown_parent_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :inner_lateral
      assert issue.meta.reason == :literal_true_on
    end

    test "passes when a correlated left lateral join uses a literal true on expression" do
      query =
        from(post in Post,
          as: :post,
          left_lateral_join: comment in subquery(comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes when a lateral subquery is correlated through a join predicate" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(join_correlated_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "returns an issue when a lateral subquery has an uncorrelated or branch" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(partly_correlated_or_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :inner_lateral
      assert issue.meta.reason == :literal_true_on
    end

    test "passes when every lateral subquery or branch is correlated" do
      query =
        from(post in Post,
          as: :post,
          inner_lateral_join: comment in subquery(correlated_or_comment_id_subquery()),
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
    end

    test "passes when a correlated cross_lateral_join references a parent binding" do
      query =
        from(post in Post,
          as: :post,
          cross_lateral_join: comment_id in subquery(comment_id_subquery()),
          select: {post.id, comment_id.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, [])
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

    test "detects literal true joins in supported raw query maps" do
      query = %{
        joins: [
          %{
            qual: :inner,
            on: %{expr: true}
          }
        ]
      }

      assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(:all, query, [])

      assert issue.meta.join_index == 0
      assert issue.meta.binding_index == 1
      assert issue.meta.join_qual == :inner
      assert issue.meta.reason == :literal_true_on
    end

    test "detects cross joins in supported raw query maps" do
      query = %{
        joins: [
          %{
            qual: :cross,
            on: %{expr: true}
          },
          %{
            qual: :cross_lateral,
            on: %{expr: true}
          }
        ]
      }

      assert {:error, [%Issue{} = first, %Issue{} = second]} =
               CartesianJoins.validate(:all, query, [])

      assert first.meta.join_index == 0
      assert first.meta.join_qual == :cross
      assert first.meta.reason == :cross_join
      assert second.meta.join_index == 1
      assert second.meta.join_qual == :cross_lateral
      assert second.meta.reason == :cross_lateral_join
    end

    test "ignores malformed raw join entries" do
      query = %{
        joins: [
          :bad,
          %{qual: :inner},
          %{on: %{expr: :not_true}}
        ]
      }

      assert :ok = CartesianJoins.validate(:all, query, [])
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

    test "passes association joins when on true is explicitly given" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          on: true,
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
        assert {:error, [%Issue{} = issue]} = CartesianJoins.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.reason == :literal_true_on
      end)
    end

    test "respects the explicit validate false option" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert :ok = CartesianJoins.validate(:all, query, validate: false)
    end

    test "validates when validate is explicitly true" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{} = issue]} =
               CartesianJoins.validate(:all, query, validate: true)

      assert issue.meta.reason == :literal_true_on
    end

    test "requires an explicit false validate option" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          select: {post.id, comment.id}
        )

      assert {:error, [%Issue{}]} =
               CartesianJoins.validate(:all, query, validate: nil)
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown option: :allow", fn ->
        CartesianJoins.validate(:all, query, allow: true)
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: :bad",
                   fn ->
                     CartesianJoins.validate(:all, query, :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [:bad]",
                   fn ->
                     CartesianJoins.validate(:all, query, [:bad])
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :bad", fn ->
        CartesianJoins.validate(:all, query, :bad)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:bad]", fn ->
        CartesianJoins.validate(:all, query, [:bad])
      end
    end
  end

  defp comment_id_subquery do
    from(comment in Comment,
      where: comment.post_id == parent_as(:post).id,
      select: %{id: comment.id}
    )
  end

  defp uncorrelated_comment_id_subquery do
    from(comment in Comment,
      select: %{id: comment.id}
    )
  end

  defp parent_projecting_comment_id_subquery do
    from(comment in Comment,
      select: %{id: comment.id, parent_post_id: parent_as(:post).id}
    )
  end

  defp parent_comparing_comment_id_subquery do
    from(comment in Comment,
      where: parent_as(:post).id == parent_as(:post).id,
      select: %{id: comment.id}
    )
  end

  defp dynamic_parent_comment_id_subquery do
    from(comment in Comment,
      where: comment.post_id == field(parent_as(:post), :id),
      select: %{id: comment.id}
    )
  end

  defp dynamic_local_comment_id_subquery do
    from(comment in Comment,
      where: field(comment, :post_id) == parent_as(:post).id,
      select: %{id: comment.id}
    )
  end

  defp named_local_comment_id_subquery do
    from(comment in Comment,
      as: :comment,
      where: as(:comment).post_id == parent_as(:post).id,
      select: %{id: comment.id}
    )
  end

  defp parent_left_comment_id_subquery do
    from(comment in Comment,
      where: parent_as(:post).id == comment.post_id,
      select: %{id: comment.id}
    )
  end

  defp unknown_parent_comment_id_subquery do
    from(comment in Comment,
      where: comment.post_id == parent_as(:missing).id,
      select: %{id: comment.id}
    )
  end

  defp partly_correlated_or_comment_id_subquery do
    from(comment in Comment,
      where: comment.post_id == parent_as(:post).id or comment.body == "public",
      select: %{id: comment.id}
    )
  end

  defp correlated_or_comment_id_subquery do
    from(comment in Comment,
      where: comment.post_id == parent_as(:post).id or comment.body == parent_as(:post).title,
      select: %{id: comment.id}
    )
  end

  defp join_correlated_comment_id_subquery do
    from(comment in Comment,
      join: post in Post,
      on: post.id == parent_as(:post).id and comment.post_id == post.id,
      select: %{id: comment.id}
    )
  end
end
