defmodule Bylaw.Ecto.Query.Checks.LeftJoinWherePredicatesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)

      has_many(:comments, Bylaw.Ecto.Query.Checks.LeftJoinWherePredicatesTest.Comment)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:status, Ecto.Enum, values: [:draft, :published, :hidden])
      field(:body, :string)
      field(:visible, :boolean)

      belongs_to(:post, Bylaw.Ecto.Query.Checks.LeftJoinWherePredicatesTest.Post)
    end
  end

  defmodule Reaction do
    use Ecto.Schema

    schema "reactions" do
      field(:post_id, :integer)
      field(:kind, :string)
    end
  end

  describe "validate/3" do
    test "returns an issue when a left join binding is filtered in where" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.check == LeftJoinWherePredicates
      assert issue.meta.operation == :all
      assert issue.meta.join_index == 0
      assert issue.meta.binding_index == 1
      assert issue.meta.join_qual == :left
      assert issue.meta.rejecting_where_fields == [:status]

      assert issue.message ==
               "expected left join binding 1 filters to stay in join on clauses; rejecting where fields: :status"
    end

    test "passes when the left join filter is in the on clause" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id and comment.status == ^status
        )

      assert :ok = LeftJoinWherePredicates.validate(:all, query, [])
    end

    test "passes when an inner join binding is filtered in where" do
      status = :published

      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status
        )

      assert :ok = LeftJoinWherePredicates.validate(:all, query, [])
    end

    test "passes when where predicates only reference the root binding" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: post.title == ^"hello"
        )

      assert :ok = LeftJoinWherePredicates.validate(:all, query, [])
    end

    test "passes for anti-join predicates that keep unmatched left join rows intentional" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: is_nil(comment.id)
        )

      assert :ok = LeftJoinWherePredicates.validate(:all, query, [])
    end

    test "returns an issue for not null predicates on left join bindings" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: not is_nil(comment.id)
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:id]
    end

    test "returns an issue for bare predicates on left join bindings" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.visible
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:visible]
    end

    test "returns an issue for in predicates on left join bindings" do
      statuses = [:published, :hidden]

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status in ^statuses
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "returns an issue for not in predicates on left join bindings" do
      statuses = [:hidden]

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status not in ^statuses
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "returns an issue for not equal predicates on left join bindings" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status != ^:hidden
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "returns an issue for range comparisons on left join bindings" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.id > ^0
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:id]
    end

    test "returns an issue for negated bare predicates on left join bindings" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: not comment.visible
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:visible]
    end

    test "returns an issue when the left join field is on the right side of a comparison" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: ^status == comment.status
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "returns an issue for self comparisons on left join bindings" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == comment.status
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "returns an issue for field-to-field comparisons involving left join bindings" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.body == post.title
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:body]
    end

    test "passes when an or branch preserves unmatched left join rows" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: is_nil(comment.id) or comment.status == ^status
        )

      assert :ok = LeftJoinWherePredicates.validate(:all, query, [])
    end

    test "passes when an or_where branch preserves unmatched left join rows" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status,
          or_where: is_nil(comment.id)
        )

      assert :ok = LeftJoinWherePredicates.validate(:all, query, [])
    end

    test "returns an issue when every or branch rejects the left join binding" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status or comment.body == ^"hello"
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:body, :status]
    end

    test "returns an issue when every or_where branch rejects the left join binding" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status,
          or_where: comment.body == ^"hello"
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:body, :status]
    end

    test "returns an issue when a later and predicate rejects a null-preserving or branch" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: is_nil(comment.id) or comment.status == ^status,
          where: comment.visible
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:status, :visible]
    end

    test "supports named left join bindings in where predicates" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          as: :comment,
          on: comment.post_id == post.id,
          where: as(:comment).status == ^status
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.binding_index == 1
      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "supports field expressions for left join bindings in where predicates" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: field(comment, :post_id) == post.id,
          where: field(comment, :status) == ^status
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "supports dynamic left join predicates in where clauses" do
      status = :published
      predicate = dynamic([_post, comment], comment.status == ^status)

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: ^predicate
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "validates association left joins" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in assoc(post, :comments),
          where: comment.status == ^status
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.binding_index == 1
      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "validates schema-less left joins" do
      query =
        from(post in "posts",
          left_join: comment in "comments",
          on: field(comment, :post_id) == field(post, :id),
          where: field(comment, :status) == ^"published"
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.binding_index == 1
      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "validates subquery left joins" do
      comments_query = from(comment in Comment, where: comment.visible == ^true)

      query =
        from(post in Post,
          left_join: comment in subquery(comments_query),
          on: comment.post_id == post.id,
          where: field(comment, :status) == ^"published"
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.binding_index == 1
      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "validates left lateral joins" do
      comments_query = from(comment in Comment)

      query =
        from(post in Post,
          left_lateral_join: comment in subquery(comments_query),
          on: true,
          where: field(comment, :status) == ^"published"
        )

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.join_qual == :left_lateral
      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "ignores left join fields hidden inside fragments" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: fragment("? = ?", comment.status, ^"published")
        )

      assert :ok = LeftJoinWherePredicates.validate(:all, query, [])
    end

    test "returns multiple issues when multiple left joins are filtered in where" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          left_join: reaction in Reaction,
          on: reaction.post_id == post.id,
          where: comment.status == ^status and reaction.kind == ^"like"
        )

      assert {:error, [%Issue{} = first_issue, %Issue{} = second_issue]} =
               LeftJoinWherePredicates.validate(:all, query, [])

      assert first_issue.meta.join_index == 0
      assert first_issue.meta.binding_index == 1
      assert first_issue.meta.rejecting_where_fields == [:status]

      assert second_issue.meta.join_index == 1
      assert second_issue.meta.binding_index == 2
      assert second_issue.meta.rejecting_where_fields == [:kind]
    end

    test "passes for every Ecto prepare_query operation when no left join where filter exists" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok = LeftJoinWherePredicates.validate(operation, query, [])
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when a left join where filter exists" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} =
                 LeftJoinWherePredicates.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.rejecting_where_fields == [:status]
      end)
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok = LeftJoinWherePredicates.validate(:all, :not_a_query, [])
    end

    test "detects left join where filters in supported raw query maps" do
      query = %{
        aliases: %{},
        joins: [
          %{qual: :left}
        ],
        wheres: [
          %{
            op: :and,
            expr: {:==, [], [join_field(:status), pinned_param(0)]}
          }
        ]
      }

      assert {:error, %Issue{} = issue} = LeftJoinWherePredicates.validate(:all, query, [])

      assert issue.meta.binding_index == 1
      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "ignores malformed raw where entries" do
      query = %{
        aliases: %{},
        joins: [
          %{qual: :left}
        ],
        wheres: [
          %{op: :and}
        ]
      }

      assert :ok = LeftJoinWherePredicates.validate(:all, query, [])
    end

    test "can be disabled explicitly" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status
        )

      assert :ok =
               LeftJoinWherePredicates.validate(:all, query,
                 left_join_where_predicates: [validate: false]
               )
    end

    test "validates when validate is explicitly true" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status
        )

      assert {:error, %Issue{} = issue} =
               LeftJoinWherePredicates.validate(:all, query,
                 left_join_where_predicates: [validate: true]
               )

      assert issue.meta.rejecting_where_fields == [:status]
    end

    test "requires an explicit false escape hatch" do
      status = :published

      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          where: comment.status == ^status
        )

      assert {:error, %Issue{}} =
               LeftJoinWherePredicates.validate(:all, query,
                 left_join_where_predicates: [validate: nil]
               )
    end

    test "raises for unknown check options" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "unknown :left_join_where_predicates option: :unknown",
                   fn ->
                     LeftJoinWherePredicates.validate(:all, query,
                       left_join_where_predicates: [unknown: true]
                     )
                   end
    end

    test "raises when check options are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :left_join_where_predicates opts to be a keyword list, got: true",
                   fn ->
                     LeftJoinWherePredicates.validate(:all, query,
                       left_join_where_predicates: true
                     )
                   end
    end

    test "raises when check options are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :left_join_where_predicates opts to be a keyword list, got: [true]",
                   fn ->
                     LeftJoinWherePredicates.validate(:all, query,
                       left_join_where_predicates: [true]
                     )
                   end
    end

    test "raises when opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: true",
                   fn ->
                     LeftJoinWherePredicates.validate(:all, query, true)
                   end
    end

    test "raises when opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [true]",
                   fn ->
                     LeftJoinWherePredicates.validate(:all, query, [true])
                   end
    end
  end

  defp join_field(field) do
    {{:., [], [{:&, [], [1]}, field]}, [], []}
  end

  defp pinned_param(index), do: {:^, [], [index]}
end
