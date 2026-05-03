defmodule Bylaw.Ecto.Query.Checks.DuplicateJoinsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.DuplicateJoins
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:organisation_id, :integer)
      field(:title, :string)

      has_many(:comments, Bylaw.Ecto.Query.Checks.DuplicateJoinsTest.Comment)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:organisation_id, :integer)
      field(:body, :string)
      field(:kind, :string)

      belongs_to(:post, Bylaw.Ecto.Query.Checks.DuplicateJoinsTest.Post)
    end
  end

  defmodule Reaction do
    use Ecto.Schema

    schema "reactions" do
      field(:emoji, :string)

      belongs_to(:post, Bylaw.Ecto.Query.Checks.DuplicateJoinsTest.Post)
    end
  end

  describe "validate/3" do
    test "passes when there are no joins" do
      query = from(post in Post)

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "passes when there is one join" do
      query = from(post in Post, join: comment in Comment, on: comment.post_id == post.id)

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok = DuplicateJoins.validate(:all, :not_a_query, [])
    end

    test "returns an issue when explicit schema joins are duplicated" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.check == DuplicateJoins

      assert issue.message ==
               "expected query not to repeat equivalent joins; join 1 duplicates join 0"

      assert issue.meta.operation == :all
      assert issue.meta.join_index == 1
      assert issue.meta.binding_index == 2
      assert issue.meta.original_join_index == 0
      assert issue.meta.original_binding_index == 1
      assert issue.meta.join_qual == :inner
      assert issue.meta.join_source == {nil, Comment}
      assert issue.meta.join_assoc == nil
    end

    test "returns an issue when duplicate joins use different named bindings" do
      query =
        from(post in Post,
          join: comment in Comment,
          as: :first_comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          as: :second_comment,
          on: other_comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins in supported raw query maps" do
      query = %{
        joins: [
          %{
            qual: :inner,
            source: {"comments", nil},
            on: true,
            params: [],
            hints: []
          },
          %{
            qual: :inner,
            source: {"comments", nil},
            on: true,
            params: [],
            hints: []
          }
        ]
      }

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins added through query composition" do
      query =
        Post
        |> join(:inner, [post], comment in Comment, on: comment.post_id == post.id)
        |> join(:inner, [post], other_comment in Comment, on: other_comment.post_id == post.id)

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins that reference a named root binding" do
      query =
        from(post in Post,
          as: :post,
          join: comment in Comment,
          on: comment.post_id == as(:post).id,
          join: other_comment in Comment,
          on: other_comment.post_id == as(:post).id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins when root binding and named root binding are mixed" do
      query =
        from(post in Post,
          as: :post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: other_comment.post_id == as(:post).id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "passes when the same schema is joined with different predicates" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: organisation_comment in Comment,
          on: organisation_comment.organisation_id == post.organisation_id
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "passes when repeated source joins target different earlier bindings" do
      query =
        from(post in Post,
          join: other_post in Post,
          on: other_post.organisation_id == post.organisation_id,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: other_comment.post_id == other_post.id
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "passes when the same source is joined with different join kinds" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          left_join: optional_comment in Comment,
          on: optional_comment.post_id == post.id
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "detects duplicate left joins" do
      query =
        from(post in Post,
          left_join: comment in Comment,
          on: comment.post_id == post.id,
          left_join: other_comment in Comment,
          on: other_comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_qual == :left
      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "passes when repeated source joins use different prefixes" do
      query =
        from(post in Post,
          join: comment in Comment,
          prefix: "tenant_a",
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          prefix: "tenant_b",
          on: other_comment.post_id == post.id
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "passes when repeated source joins use different hints" do
      query =
        from(post in Post,
          join: comment in Comment,
          hints: "USE INDEX comments_post_id",
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          hints: "USE INDEX comments_organisation_id",
          on: other_comment.post_id == post.id
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "passes when repeated source joins have different parameter values" do
      first_kind = "public"
      second_kind = "private"

      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.kind == ^first_kind,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id and other_comment.kind == ^second_kind
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "passes when repeated source joins have different structured parameter values" do
      first_value = {"marker", [1], "same"}
      second_value = {"marker", [2], "same"}

      query =
        from(post in Post,
          join: comment in Comment,
          on:
            comment.post_id == post.id and
              fragment("? = ?", comment.body, ^first_value),
          join: other_comment in Comment,
          on:
            other_comment.post_id == post.id and
              fragment("? = ?", other_comment.body, ^second_value)
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "detects duplicate joins with matching parameter values" do
      kind = "public"

      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.kind == ^kind,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id and other_comment.kind == ^kind
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "passes when repeated joins have different later predicates" do
      public_kind = "public"
      private_kind = "private"

      query =
        from(post in Post,
          join: public_comment in Comment,
          on: public_comment.post_id == post.id,
          join: private_comment in Comment,
          on: private_comment.post_id == post.id,
          where: public_comment.kind == ^public_kind,
          where: private_comment.kind == ^private_kind
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "passes when repeated joins have different later predicate boolean operators" do
      kind = "public"
      body = "hello"

      query =
        from(post in Post,
          join: first_comment in Comment,
          on: first_comment.post_id == post.id,
          join: second_comment in Comment,
          on: second_comment.post_id == post.id,
          where: first_comment.kind == ^kind or first_comment.body == ^body,
          where: second_comment.kind == ^kind and second_comment.body == ^body
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "detects duplicate joins with matching later predicates" do
      kind = "public"

      query =
        from(post in Post,
          join: first_comment in Comment,
          on: first_comment.post_id == post.id,
          join: second_comment in Comment,
          on: second_comment.post_id == post.id,
          where: first_comment.kind == ^kind,
          where: second_comment.kind == ^kind
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins with root parameter types in the on expression" do
      title = "hello"

      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and post.title == ^title,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id and post.title == ^title
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins when equality operands are reversed" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: post.id == other_comment.post_id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins when and expression terms are reordered" do
      kind = "public"

      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.kind == ^kind,
          join: other_comment in Comment,
          on: other_comment.kind == ^kind and other_comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins when parameterized and expression terms are reordered" do
      kind = "public"
      body = "hello"

      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.kind == ^kind and comment.body == ^body,
          join: other_comment in Comment,
          on:
            other_comment.body == ^body and other_comment.post_id == post.id and
              other_comment.kind == ^kind
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins with keyword on predicates" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: [post_id: post.id],
          join: other_comment in Comment,
          on: [post_id: post.id]
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins with field expressions" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: field(comment, :post_id) == field(post, :id),
          join: other_comment in Comment,
          on: field(other_comment, :post_id) == field(post, :id)
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins with on true" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          join: other_comment in Comment,
          on: true
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "detects duplicate joins against a prior non-root binding" do
      query =
        from(post in Post,
          join: reaction in Reaction,
          on: reaction.post_id == post.id,
          join: comment in Comment,
          on: comment.post_id == reaction.post_id,
          join: other_comment in Comment,
          on: other_comment.post_id == reaction.post_id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 2
      assert issue.meta.original_join_index == 1
    end

    test "detects duplicate schema-less joins" do
      query =
        from(post in "posts",
          join: comment in "comments",
          on: field(comment, :post_id) == field(post, :id),
          join: other_comment in "comments",
          on: field(other_comment, :post_id) == field(post, :id)
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_source == {"comments", nil}
    end

    test "detects duplicate association joins" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          join: other_comment in assoc(post, :comments),
          select: {comment.id, other_comment.id}
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_source == nil
      assert issue.meta.join_assoc == {0, :comments}
    end

    test "detects duplicate fragment joins" do
      query =
        from(post in "posts",
          join: comment in fragment("select * from comments"),
          on: field(comment, :post_id) == field(post, :id),
          join: other_comment in fragment("select * from comments"),
          on: field(other_comment, :post_id) == field(post, :id)
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
    end

    test "detects duplicate interpolated query joins" do
      comments_query = from(comment in Comment, where: comment.body == ^"hello")

      query =
        from(post in Post,
          join: comment in ^comments_query,
          on: comment.post_id == post.id,
          join: other_comment in ^comments_query,
          on: other_comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
    end

    test "detects duplicate subquery joins" do
      comments_query = from(comment in Comment, where: comment.body == ^"hello")

      query =
        from(post in Post,
          join: comment in subquery(comments_query),
          on: comment.post_id == post.id,
          join: other_comment in subquery(comments_query),
          on: other_comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
    end

    test "does not treat different subquery joins as duplicates" do
      comments_query = from(comment in Comment, where: comment.body == ^"hello")
      other_comments_query = from(comment in Comment, where: comment.body == ^"goodbye")

      query =
        from(post in Post,
          join: comment in subquery(comments_query),
          on: comment.post_id == post.id,
          join: other_comment in subquery(other_comments_query),
          on: other_comment.post_id == post.id
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "does not treat joins constrained by different later subqueries as duplicates" do
      public_comments_query =
        from(comment in Comment, where: comment.kind == "public", select: comment.id)

      private_comments_query =
        from(comment in Comment, where: comment.kind == "private", select: comment.id)

      query =
        from(post in Post,
          join: public_comment in Comment,
          on: public_comment.post_id == post.id,
          join: private_comment in Comment,
          on: private_comment.post_id == post.id,
          where: public_comment.id in subquery(public_comments_query),
          where: private_comment.id in subquery(private_comments_query)
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "does not treat joins with different source parameters as duplicates" do
      query =
        from(post in "posts",
          join: comment in values([%{post_id: 1}], %{post_id: :integer}),
          on: comment.post_id == post.id,
          join: other_comment in values([%{post_id: 2}], %{post_id: :integer}),
          on: other_comment.post_id == post.id
        )

      assert :ok = DuplicateJoins.validate(:all, query, [])
    end

    test "detects duplicate joins with matching source parameters" do
      query =
        from(post in "posts",
          join: comment in values([%{post_id: 1}], %{post_id: :integer}),
          on: comment.post_id == post.id,
          join: other_comment in values([%{post_id: 1}], %{post_id: :integer}),
          on: other_comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} = DuplicateJoins.validate(:all, query, [])

      assert issue.meta.join_index == 1
      assert issue.meta.original_join_index == 0
    end

    test "returns multiple issues when multiple joins repeat earlier joins" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id,
          join: reaction in Reaction,
          on: reaction.post_id == post.id,
          join: other_reaction in Reaction,
          on: other_reaction.post_id == post.id
        )

      assert {:error, [%Issue{} = first_issue, %Issue{} = second_issue]} =
               DuplicateJoins.validate(:all, query, [])

      assert first_issue.meta.join_index == 1
      assert first_issue.meta.original_join_index == 0

      assert second_issue.meta.join_index == 3
      assert second_issue.meta.original_join_index == 2
    end

    test "passes for every Ecto prepare_query operation when joins are unique" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: reaction in Reaction,
          on: reaction.post_id == post.id
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok = DuplicateJoins.validate(operation, query, [])
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when joins are duplicated" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} = DuplicateJoins.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.join_index == 1
      end)
    end

    test "respects the explicit query-level escape hatch" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id
        )

      assert :ok = DuplicateJoins.validate(:all, query, validate: false)
    end

    test "validates when validate is explicitly true" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} =
               DuplicateJoins.validate(:all, query, validate: true)

      assert issue.meta.join_index == 1
    end

    test "requires an explicit false escape hatch" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: other_comment in Comment,
          on: other_comment.post_id == post.id
        )

      assert {:error, %Issue{}} =
               DuplicateJoins.validate(:all, query, validate: nil)
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown option: :sources", fn ->
        DuplicateJoins.validate(:all, query, sources: [:comments])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: :bad",
                   fn ->
                     DuplicateJoins.validate(:all, query, :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [true]",
                   fn ->
                     DuplicateJoins.validate(:all, query, [true])
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :bad", fn ->
        DuplicateJoins.validate(:all, query, :bad)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [true]", fn ->
        DuplicateJoins.validate(:all, query, [true])
      end
    end
  end
end
