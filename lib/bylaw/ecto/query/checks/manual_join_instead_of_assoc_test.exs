defmodule Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssoc
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)

      has_many(:comments, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Comment)
      has_many(:comment_authors, through: [:comments, :author])

      many_to_many(:tags, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Tag,
        join_through: "posts_tags"
      )
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:body, :string)
      field(:public, :boolean)

      belongs_to(:post, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Post)
      belongs_to(:author, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Author)
    end
  end

  defmodule Author do
    use Ecto.Schema

    schema "authors" do
      field(:name, :string)
    end
  end

  defmodule Tag do
    use Ecto.Schema

    schema "tags" do
      field(:name, :string)
    end
  end

  defmodule MultiAssociationPost do
    use Ecto.Schema

    schema "multi_association_posts" do
      has_many(:comments, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Comment,
        foreign_key: :post_id
      )

      has_many(:public_comments, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Comment,
        foreign_key: :post_id
      )
    end
  end

  defmodule FilteredAssociationPost do
    use Ecto.Schema

    schema "filtered_association_posts" do
      has_many(:public_comments, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Comment,
        foreign_key: :post_id,
        where: [public: true]
      )

      has_many(:public_comment_authors, through: [:public_comments, :author])
    end
  end

  defmodule MixedFilteredAssociationPost do
    use Ecto.Schema

    schema "mixed_filtered_association_posts" do
      has_many(:comments, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Comment,
        foreign_key: :post_id
      )

      has_many(:public_comments, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Comment,
        foreign_key: :post_id,
        where: [public: true]
      )
    end
  end

  defmodule JoinFilteredManyToManyPost do
    use Ecto.Schema

    schema "join_filtered_many_to_many_posts" do
      many_to_many(:published_tags, Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.Tag,
        join_through: "posts_tags",
        join_where: [published: true]
      )
    end
  end

  defmodule ReverseOnlyPost do
    use Ecto.Schema

    schema "reverse_only_posts" do
      field(:title, :string)
    end
  end

  defmodule ReverseOnlyComment do
    use Ecto.Schema

    schema "reverse_only_comments" do
      field(:body, :string)

      belongs_to(
        :reverse_only_post,
        Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssocTest.ReverseOnlyPost
      )
    end
  end

  describe "validate/3" do
    test "returns an issue when a manual join targets a root association schema" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.check == ManualJoinInsteadOfAssoc

      assert issue.message ==
               "expected join 0 to use assoc/2 for existing association :comments from #{inspect(Post)} to #{inspect(Comment)}"

      assert issue.meta.operation == :all
      assert issue.meta.join_index == 0
      assert issue.meta.binding_index == 1
      assert issue.meta.join_qual == :inner
      assert issue.meta.root_schema == Post
      assert issue.meta.join_schema == Comment
      assert issue.meta.associations == [:comments]
      assert issue.meta.join_source == {nil, Comment}
    end

    test "returns an issue when a manual join targets a belongs_to association from the root" do
      query =
        from(comment in Comment,
          join: author in Author,
          on: author.id == comment.author_id,
          select: {comment.id, author.id}
        )

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.message ==
               "expected join 0 to use assoc/2 for existing association :author from #{inspect(Comment)} to #{inspect(Author)}"

      assert issue.meta.root_schema == Comment
      assert issue.meta.join_schema == Author
      assert issue.meta.associations == [:author]
    end

    test "returns an issue when a manual join targets a many_to_many association schema" do
      query =
        from(post in Post,
          join: tag in Tag,
          on: true,
          select: {post.id, tag.id}
        )

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.root_schema == Post
      assert issue.meta.join_schema == Tag
      assert issue.meta.associations == [:tags]
    end

    test "returns an issue when a manual join targets a through association schema" do
      query =
        from(post in Post,
          join: author in Author,
          on: true,
          select: {post.id, author.id}
        )

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.root_schema == Post
      assert issue.meta.join_schema == Author
      assert issue.meta.associations == [:comment_authors]
    end

    test "passes when the join already uses assoc/2" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          select: {post.id, comment.id}
        )

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "returns an issue when a manual associated join is added through query composition" do
      query =
        Post
        |> join(:inner, [post], comment in Comment, on: comment.post_id == post.id)
        |> select([post, comment], {post.id, comment.id})

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.join_index == 0
      assert issue.meta.associations == [:comments]
    end

    test "returns an issue for supported raw query maps with manual associated joins" do
      query = query_with_join(%{assoc: nil, source: {nil, Comment}, qual: :inner})

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.root_schema == Post
      assert issue.meta.join_schema == Comment
      assert issue.meta.join_qual == :inner
      assert issue.meta.associations == [:comments]
    end

    test "returns an issue for supported raw join maps without an assoc key" do
      query = query_with_join(%{source: {nil, Comment}, qual: :inner})

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.root_schema == Post
      assert issue.meta.join_schema == Comment
      assert issue.meta.associations == [:comments]
    end

    test "passes supported raw association join maps" do
      query = query_with_join(%{assoc: {0, :comments}, source: {nil, Comment}, qual: :inner})

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "returns every matching root association for a joined schema" do
      query =
        from(post in MultiAssociationPost,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.associations == [:comments, :public_comments]

      assert issue.message ==
               "expected join 0 to use assoc/2 for one of existing associations :comments, :public_comments from #{inspect(MultiAssociationPost)} to #{inspect(Comment)}"
    end

    test "passes when the only matching root association has a where filter" do
      query =
        from(post in FilteredAssociationPost,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.public == false,
          select: {post.id, comment.id}
        )

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "does not suggest filtered associations when an unfiltered association also matches" do
      query =
        from(post in MixedFilteredAssociationPost,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.associations == [:comments]

      assert issue.message ==
               "expected join 0 to use assoc/2 for existing association :comments from #{inspect(MixedFilteredAssociationPost)} to #{inspect(Comment)}"
    end

    test "passes when a matching through association depends on a filtered step" do
      query =
        from(post in FilteredAssociationPost,
          join: author in Author,
          on: true,
          select: {post.id, author.id}
        )

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "passes when the only matching many_to_many association has a join_where filter" do
      query =
        from(post in JoinFilteredManyToManyPost,
          join: tag in Tag,
          on: true,
          select: {post.id, tag.id}
        )

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "passes when the root schema has no association to the joined schema" do
      query =
        from(post in ReverseOnlyPost,
          join: comment in ReverseOnlyComment,
          on: comment.reverse_only_post_id == post.id,
          select: {post.id, comment.id}
        )

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "passes when there are no joins" do
      query = from(post in Post)

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, :not_a_query, [])
    end

    test "passes schema-less Ecto queries" do
      query =
        from(post in "posts",
          join: comment in Comment,
          on: field(comment, :post_id) == field(post, :id),
          select: {field(post, :id), comment.id}
        )

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "passes subquery joins even when the subquery selects an associated schema" do
      comments_query =
        from(comment in Comment, select: %{id: comment.id, post_id: comment.post_id})

      query =
        from(post in Post,
          join: comment in subquery(comments_query),
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "passes schema-less, fragment, and malformed joins" do
      query = %{
        from: %{source: {"posts", Post}},
        joins: [
          %{assoc: nil, source: {"comments", nil}},
          %{assoc: nil, source: {:fragment, [], [raw: "select * from comments"]}},
          :not_a_join
        ]
      }

      assert :ok = ManualJoinInsteadOfAssoc.validate(:all, query, [])
    end

    test "returns one issue per manual associated join" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: tag in Tag,
          on: true,
          select: {post.id, comment.id, tag.id}
        )

      assert {:error, [%Issue{}, %Issue{}] = issues} =
               ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert Enum.map(issues, & &1.meta.join_index) == [0, 1]
      assert Enum.map(issues, & &1.meta.associations) == [[:comments], [:tags]]
    end

    test "returns an issue when a set operation branch has a manual associated join" do
      safe_query = from(post in Post, select: post.id)

      manual_join_query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: post.id
        )

      query = union_all(safe_query, ^manual_join_query)

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.join_index == 0
      assert issue.meta.associations == [:comments]

      assert issue.meta.combination_path == [
               %{operation: :union_all, index: 0}
             ]
    end

    test "returns every issue when the root and a set operation branch have manual associated joins" do
      root_manual_join_query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: post.id
        )

      branch_manual_join_query =
        from(post in Post,
          join: tag in Tag,
          on: true,
          select: post.id
        )

      query = union_all(root_manual_join_query, ^branch_manual_join_query)

      assert {:error, [%Issue{} = root_issue, %Issue{} = branch_issue]} =
               ManualJoinInsteadOfAssoc.validate(:all, query, [])

      refute Map.has_key?(root_issue.meta, :combination_path)
      assert root_issue.meta.join_index == 0
      assert root_issue.meta.associations == [:comments]

      assert branch_issue.meta.join_index == 0
      assert branch_issue.meta.associations == [:tags]
      assert branch_issue.meta.combination_path == [%{operation: :union_all, index: 0}]
    end

    test "tracks nested set operation branches with manual associated joins" do
      safe_query = from(post in Post, select: post.id)

      manual_join_query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: post.id
        )

      nested_query = union_all(safe_query, ^manual_join_query)
      query = union(safe_query, ^nested_query)

      assert {:error, %Issue{} = issue} = ManualJoinInsteadOfAssoc.validate(:all, query, [])

      assert issue.meta.join_index == 0
      assert issue.meta.associations == [:comments]

      assert issue.meta.combination_path == [
               %{operation: :union, index: 0},
               %{operation: :union_all, index: 0}
             ]
    end

    test "passes for every Ecto prepare_query operation when joins use assoc/2" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          select: {post.id, comment.id}
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok = ManualJoinInsteadOfAssoc.validate(operation, query, [])
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when a manual associated join exists" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} =
                 ManualJoinInsteadOfAssoc.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.associations == [:comments]
      end)
    end

    test "skips validation when disabled" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      assert :ok =
               ManualJoinInsteadOfAssoc.validate(:all, query,
                 manual_join_instead_of_assoc: [validate: false]
               )
    end

    test "validates when validate is explicitly true" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{}} =
               ManualJoinInsteadOfAssoc.validate(:all, query,
                 manual_join_instead_of_assoc: [validate: true]
               )
    end

    test "requires an explicit false escape hatch" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          select: {post.id, comment.id}
        )

      assert {:error, %Issue{}} =
               ManualJoinInsteadOfAssoc.validate(:all, query,
                 manual_join_instead_of_assoc: [validate: nil]
               )
    end

    test "raises when opts are not a keyword list" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        ManualJoinInsteadOfAssoc.validate(:all, from(post in Post), :invalid)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        ManualJoinInsteadOfAssoc.validate(:all, from(post in Post), [:invalid])
      end
    end

    test "raises when check opts are not a keyword list" do
      assert_raise ArgumentError,
                   "expected :manual_join_instead_of_assoc opts to be a keyword list, got: :invalid",
                   fn ->
                     ManualJoinInsteadOfAssoc.validate(:all, from(post in Post),
                       manual_join_instead_of_assoc: :invalid
                     )
                   end
    end

    test "raises when check opts are a non-keyword list" do
      assert_raise ArgumentError,
                   "expected :manual_join_instead_of_assoc opts to be a keyword list, got: [:invalid]",
                   fn ->
                     ManualJoinInsteadOfAssoc.validate(:all, from(post in Post),
                       manual_join_instead_of_assoc: [:invalid]
                     )
                   end
    end

    test "raises when namespaced options contain unsupported keys" do
      assert_raise ArgumentError,
                   "unknown :manual_join_instead_of_assoc option: :fields",
                   fn ->
                     ManualJoinInsteadOfAssoc.validate(:all, from(post in Post),
                       manual_join_instead_of_assoc: [fields: [:comments]]
                     )
                   end
    end
  end

  defp query_with_join(join) do
    %{
      aliases: %{},
      from: %{source: {"posts", Post}},
      joins: [join]
    }
  end
end
