defmodule Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicatesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:organisation_id, :integer)
      field(:deleted_at, :utc_datetime)
      field(:archived_at, :utc_datetime)
      field(:published_at, :utc_datetime)
      field(:status, Ecto.Enum, values: [:draft, :published, :hidden])
      field(:title, :string)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:deleted_at, :utc_datetime)
      field(:status, Ecto.Enum, values: [:published, :hidden])
      field(:post_id, :integer)
    end
  end

  defmodule PublishedPost do
    use Ecto.Schema

    schema "published_posts" do
      field(:published_at, :utc_datetime)
      field(:title, :string)
    end
  end

  defmodule GlobalPost do
    use Ecto.Schema

    schema "global_posts" do
      field(:title, :string)
    end
  end

  defmodule NotSchema do
  end

  describe "validate/3" do
    test "passes when configured fields are explicitly constrained" do
      query =
        from(post in Post,
          where: is_nil(post.deleted_at),
          where: post.status == ^:published
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when configured fields use not null and in predicates" do
      statuses = [:published]

      query =
        from(post in Post,
          where: not is_nil(post.deleted_at),
          where: post.status in ^statuses
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when configured fields use comparison and not equal predicates" do
      cutoff = ~U[2026-01-01 00:00:00Z]

      query =
        from(post in Post,
          where: post.deleted_at <= ^cutoff and post.status != ^:draft
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when configured fields use keyword where syntax" do
      deleted_at = ~U[2026-01-01 00:00:00Z]
      query = from(post in Post, where: [deleted_at: ^deleted_at, status: ^:published])

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when configured fields appear as bare predicates" do
      query =
        from(post in Post,
          where: post.deleted_at,
          where: post.status
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when configured fields appear as negated bare predicates" do
      query =
        from(post in Post,
          where: not post.deleted_at,
          where: not post.status
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when configured fields are on the right side of equality predicates" do
      deleted_at = ~U[2026-01-01 00:00:00Z]

      query =
        from(post in Post,
          where: ^deleted_at == post.deleted_at,
          where: ^:published == post.status
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "does not accept visibility fields in self comparisons" do
      query =
        from(post in Post,
          where: post.deleted_at == post.deleted_at,
          where: post.status == post.status
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "does not accept visibility fields compared to other root fields" do
      query =
        from(post in Post,
          where: post.deleted_at == post.archived_at,
          where: post.status == post.title
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "does not accept visibility fields compared to joined fields" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          where: is_nil(post.deleted_at),
          where: post.status == comment.status
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:status]
      assert issue.meta.found_visibility_fields == [:deleted_at]
    end

    test "does not accept visibility fields in in predicates compared to root fields" do
      query =
        from(post in Post,
          where: is_nil(post.deleted_at),
          where: post.status in [post.status]
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:status]
      assert issue.meta.found_visibility_fields == [:deleted_at]
    end

    test "passes when configured fields use not in predicates" do
      deleted_at = ~U[2026-01-01 00:00:00Z]
      statuses = [:hidden]

      query =
        from(post in Post,
          where: post.deleted_at not in ^[deleted_at],
          where: post.status not in ^statuses
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when configured fields are present in a dynamic where expression" do
      status = :published
      predicate = dynamic([post], is_nil(post.deleted_at) and post.status == ^status)
      query = from(post in Post, where: ^predicate)

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when configured fields are referenced with field/2" do
      query =
        from(post in Post,
          where: is_nil(field(post, :deleted_at)),
          where: field(post, :status) == ^:published
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "does not accept field/2 visibility fields compared to other root fields" do
      query =
        from(post in Post,
          where: is_nil(field(post, :deleted_at)),
          where: field(post, :status) == field(post, :title)
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:status]
      assert issue.meta.found_visibility_fields == [:deleted_at]
    end

    test "passes when configured fields are referenced from named root bindings" do
      query =
        from(post in Post,
          as: :post,
          where: is_nil(as(:post).deleted_at),
          where: as(:post).status == ^:published
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when field/2 references named root bindings" do
      query =
        from(post in Post,
          as: :post,
          where: is_nil(field(as(:post), :deleted_at)),
          where: field(as(:post), :status) == ^:published
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "does not accept field/2 visibility fields compared to named root fields" do
      query =
        from(post in Post,
          as: :post,
          where: is_nil(field(as(:post), :deleted_at)),
          where: field(as(:post), :status) == field(as(:post), :title)
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:status]
      assert issue.meta.found_visibility_fields == [:deleted_at]
    end

    test "passes for every Ecto prepare_query operation when explicit predicates are present" do
      query =
        from(post in Post,
          where: is_nil(post.deleted_at),
          where: post.status == ^:published
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok = ExplicitVisibilityPredicates.validate(operation, query, opts())
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when predicates are missing" do
      query = from(post in Post)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, [%Issue{} = issue]} =
                 ExplicitVisibilityPredicates.validate(operation, query, opts())

        assert issue.meta.operation == operation
        assert issue.meta.missing_fields == [:deleted_at, :status]
      end)
    end

    test "returns an issue when there is no where clause" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.check == ExplicitVisibilityPredicates
      assert issue.meta.root_schema == Post
      assert issue.meta.configured_fields == [:deleted_at, :status]
      assert issue.meta.applicable_fields == [:deleted_at, :status]
      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)

      assert issue.message ==
               "expected query to explicitly constrain visibility-sensitive fields: :deleted_at, :status"
    end

    test "returns an issue when only tenant scope is present" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "returns an issue when only one configured field is constrained" do
      query = from(post in Post, where: is_nil(post.deleted_at))

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:status]
      assert issue.meta.found_visibility_fields == [:deleted_at]

      assert issue.message ==
               "expected query to explicitly constrain visibility-sensitive fields: :status"
    end

    test "passes when the root schema is not configured" do
      query = from(comment in Comment, where: is_nil(comment.deleted_at))

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when no schemas are configured" do
      query = from(post in Post)

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query, schemas: [])
    end

    test "passes when check options are omitted" do
      query = from(post in Post)

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, [])
    end

    test "uses the matching root schema from multiple schema configs" do
      query = from(comment in Comment, where: is_nil(comment.deleted_at))

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query,
                 schemas: [
                   {Post, fields: [:deleted_at, :status]},
                   {Comment, fields: [:deleted_at]}
                 ]
               )
    end

    test "returns an issue for the matching root schema from multiple schema configs" do
      query = from(comment in Comment)

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query,
                 schemas: [
                   {Post, fields: [:deleted_at, :status]},
                   {Comment, fields: [:deleted_at]}
                 ]
               )

      assert issue.meta.root_schema == Comment
      assert issue.meta.configured_fields == [:deleted_at]
      assert issue.meta.applicable_fields == [:deleted_at]
      assert issue.meta.missing_fields == [:deleted_at]
    end

    test "passes when configured fields do not exist on the root schema" do
      query = from(post in GlobalPost, where: post.title == ^"hello")

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query,
                 schemas: [{GlobalPost, fields: [:deleted_at, :status]}]
               )
    end

    test "validates only configured fields that exist on the root schema" do
      query = from(post in PublishedPost, where: not is_nil(post.published_at))

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query,
                 schemas: [{PublishedPost, fields: [:deleted_at, :published_at]}]
               )
    end

    test "returns an issue when an applicable configured field is missing" do
      query = from(post in PublishedPost, where: post.title == ^"hello")

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query,
                 schemas: [{PublishedPost, fields: [:deleted_at, :published_at]}]
               )

      assert issue.meta.configured_fields == [:deleted_at, :published_at]
      assert issue.meta.applicable_fields == [:published_at]
      assert issue.meta.missing_fields == [:published_at]
    end

    test "passes for schema-less sources because configuration is schema-by-schema" do
      query = from(post in "posts")

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when query is not an Ecto query struct" do
      assert :ok = ExplicitVisibilityPredicates.validate(:all, :not_a_query, opts())
    end

    test "passes source subqueries because configuration is schema-by-schema" do
      scoped_posts =
        from(post in Post,
          where: is_nil(post.deleted_at),
          where: post.status == ^:published
        )

      query = from(post in subquery(scoped_posts), select: count())

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when every combination branch constrains visibility fields" do
      scoped_posts =
        from(post in Post,
          where: is_nil(post.deleted_at) and post.status == ^:published,
          select: post.id
        )

      hidden_posts =
        from(post in Post,
          where: not is_nil(post.deleted_at) and post.status == ^:hidden,
          select: post.id
        )

      query = union_all(scoped_posts, ^hidden_posts)

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "returns an issue when a combination branch is missing visibility fields" do
      scoped_posts =
        from(post in Post,
          where: is_nil(post.deleted_at) and post.status == ^:published,
          select: post.id
        )

      unscoped_posts =
        from(post in Post,
          where: post.title == ^"public",
          select: post.id
        )

      scoped_posts
      |> combination_queries(unscoped_posts)
      |> Enum.each(fn {operation, query} ->
        assert {:error, [%Issue{} = issue]} =
                 ExplicitVisibilityPredicates.validate(:all, query, opts())

        assert issue.meta.root_schema == Post
        assert issue.meta.missing_fields == [:deleted_at, :status]
        assert Enum.empty?(issue.meta.found_visibility_fields)
        assert issue.meta.combination_path == [%{operation: operation, index: 0}]
      end)
    end

    test "validates configured combination branches when the parent schema is not configured" do
      comments =
        from(comment in Comment,
          where: comment.post_id == ^123,
          select: comment.post_id
        )

      unscoped_posts =
        from(post in Post,
          where: post.title == ^"public",
          select: post.id
        )

      query = union_all(comments, ^unscoped_posts)

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.root_schema == Post
      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert issue.meta.combination_path == [%{operation: :union_all, index: 0}]
    end

    test "returns every issue when the root and a combination branch miss visibility fields" do
      unscoped_posts =
        from(post in Post,
          where: post.title == ^"public",
          select: post.id
        )

      other_unscoped_posts =
        from(post in Post,
          where: post.title == ^"private",
          select: post.id
        )

      query = union_all(unscoped_posts, ^other_unscoped_posts)

      assert {:error, [%Issue{} = root_issue, %Issue{} = combination_issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      refute Map.has_key?(root_issue.meta, :combination_path)
      assert root_issue.meta.missing_fields == [:deleted_at, :status]

      assert combination_issue.meta.missing_fields == [:deleted_at, :status]
      assert combination_issue.meta.combination_path == [%{operation: :union_all, index: 0}]
    end

    test "tracks nested combination branches missing visibility fields" do
      scoped_posts =
        from(post in Post,
          where: is_nil(post.deleted_at) and post.status == ^:published,
          select: post.id
        )

      unscoped_posts =
        from(post in Post,
          where: post.title == ^"public",
          select: post.id
        )

      nested_query = union_all(scoped_posts, ^unscoped_posts)
      query = union(scoped_posts, ^nested_query)

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]

      assert issue.meta.combination_path == [
               %{operation: :union, index: 0},
               %{operation: :union_all, index: 0}
             ]
    end

    test "does not require configured joined schemas" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          where: is_nil(post.deleted_at),
          where: post.status == ^:published
        )

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query,
                 schemas: [
                   {Post, fields: [:deleted_at, :status]},
                   {Comment, fields: [:deleted_at, :status]}
                 ]
               )
    end

    test "does not accept visibility fields from non-root bindings" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: is_nil(comment.deleted_at),
          where: comment.status == ^:published
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "does not accept visibility fields from non-root field expressions" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: is_nil(field(comment, :deleted_at)),
          where: field(comment, :status) == ^:published
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "accepts visibility fields from the root binding when joins are present" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          where: is_nil(post.deleted_at),
          where: post.status == ^:published
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "does not accept visibility fields that only appear in join predicates" do
      query =
        from(post in Post,
          join: comment in Comment,
          on:
            comment.post_id == post.id and is_nil(post.deleted_at) and
              post.status == ^:published
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "does not accept visibility fields from named non-root bindings" do
      query =
        from(post in Post,
          as: :post,
          join: comment in Comment,
          as: :comment,
          on: true,
          where: is_nil(as(:comment).deleted_at),
          where: as(:comment).status == ^:published
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "does not accept visibility fields that only appear outside where predicates" do
      query =
        from(post in Post,
          order_by: [asc: post.status],
          select: {post.deleted_at, post.status}
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "does not accept visibility fields that only appear in an or_where branch" do
      query =
        from(post in Post,
          where: post.title == ^"hello",
          or_where: is_nil(post.deleted_at) and post.status == ^:published
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "does not accept visibility fields when an or_where branch can match without them" do
      query =
        from(post in Post,
          where: is_nil(post.deleted_at) and post.status == ^:published,
          or_where: post.title == ^"hello"
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "requires every visibility field to be present in every or_where branch" do
      query =
        from(post in Post,
          where: is_nil(post.deleted_at),
          or_where: post.status == ^:published
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "passes when every or_where branch constrains visibility fields" do
      query =
        from(post in Post,
          where: is_nil(post.deleted_at) and post.status == ^:published,
          or_where: not is_nil(post.deleted_at) and post.status == ^:hidden
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "passes when an initial or_where branch constrains visibility fields" do
      query =
        from(post in Post,
          or_where: is_nil(post.deleted_at) and post.status == ^:published
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "does not accept visibility fields when an or expression branch can match without them" do
      query =
        from(post in Post,
          where:
            (is_nil(post.deleted_at) and post.status == ^:published) or post.title == ^"hello"
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "requires every visibility field to be present in every or expression branch" do
      query =
        from(post in Post,
          where: is_nil(post.deleted_at) or post.status == ^:published
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "passes when every or expression branch constrains visibility fields" do
      query =
        from(post in Post,
          where:
            (is_nil(post.deleted_at) and post.status == ^:published) or
              (not is_nil(post.deleted_at) and post.status == ^:hidden)
        )

      assert :ok = ExplicitVisibilityPredicates.validate(:all, query, opts())
    end

    test "does not accept visibility fields hidden inside fragments" do
      query =
        from(post in Post,
          where: fragment("? IS NULL", post.deleted_at),
          where: fragment("? = ?", post.status, ^"published")
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "does not accept visibility fields hidden inside exists subqueries" do
      query =
        from(post in Post,
          where:
            exists(
              from(other_post in Post,
                where: is_nil(other_post.deleted_at) and other_post.status == ^:published
              )
            )
        )

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query, opts())

      assert issue.meta.missing_fields == [:deleted_at, :status]
      assert Enum.empty?(issue.meta.found_visibility_fields)
    end

    test "respects the explicit validate false option" do
      query = from(post in Post)

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query, validate: false)
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query,
                 validate: true,
                 schemas: [{Post, fields: [:deleted_at, :status]}]
               )

      assert issue.meta.missing_fields == [:deleted_at, :status]
    end

    test "requires an explicit false validate option" do
      query = from(post in Post)

      assert {:error, [%Issue{}]} =
               ExplicitVisibilityPredicates.validate(:all, query,
                 validate: nil,
                 schemas: [{Post, fields: [:deleted_at, :status]}]
               )
    end

    test "deduplicates configured fields" do
      query = from(post in Post, where: is_nil(post.deleted_at))

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query,
                 schemas: [{Post, fields: [:deleted_at, :deleted_at]}]
               )
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        ExplicitVisibilityPredicates.validate(:all, query, :invalid)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        ExplicitVisibilityPredicates.validate(:all, query, [:invalid])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: :invalid",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query, :invalid)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [:invalid]",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query, [:invalid])
                   end
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "unknown option: :fields",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query, fields: [:deleted_at])
                   end
    end

    test "raises when schemas are not a list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :schemas to be a list of {schema, fields: fields} tuples, got: Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicatesTest.Post",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query, schemas: Post)
                   end
    end

    test "raises when schema entries are malformed" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :schemas to contain {schema, fields: fields} tuples, got: Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicatesTest.Post",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query, schemas: [Post])
                   end
    end

    test "raises when configured schema is not an Ecto schema" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected configured schema to be an Ecto schema, got: Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicatesTest.NotSchema",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query,
                       schemas: [{NotSchema, fields: [:status]}]
                     )
                   end
    end

    test "raises when schema options are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected schema options for Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicatesTest.Post to be a keyword list, got: [:invalid]",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query,
                       schemas: [{Post, [:invalid]}]
                     )
                   end
    end

    test "raises when schema options include unsupported keys" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "unknown option for schema Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicatesTest.Post: :match",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query,
                       schemas: [{Post, fields: [:deleted_at], match: :all}]
                     )
                   end
    end

    test "raises when schema fields are missing" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "missing required :fields option for schema Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicatesTest.Post",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query, schemas: [{Post, []}])
                   end
    end

    test "raises when fields are empty" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: []",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query,
                       schemas: [{Post, fields: []}]
                     )
                   end
    end

    test "raises when fields are not a list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: :deleted_at",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query,
                       schemas: [{Post, fields: :deleted_at}]
                     )
                   end
    end

    test "raises when fields contain non-atoms" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   ~s(expected :fields to contain only atoms, got: "deleted_at"),
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query,
                       schemas: [{Post, fields: ["deleted_at"]}]
                     )
                   end
    end
  end

  describe "validate/3 with rules" do
    test "validates fields from matching query-local rules" do
      query = from(post in Post, where: is_nil(post.deleted_at))

      assert {:error, [%Issue{} = issue]} =
               ExplicitVisibilityPredicates.validate(:all, query,
                 rules: [[only: [ecto_schema: Post], fields: [:deleted_at, :status]]]
               )

      assert issue.meta.configured_fields == [:deleted_at, :status]
      assert issue.meta.missing_fields == [:status]
      assert issue.meta.found_visibility_fields == [:deleted_at]
    end

    test "passes when no query-local visibility rule matches" do
      query = from(post in Post)

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query,
                 rules: [[only: [table: "comments"], fields: [:deleted_at]]]
               )
    end

    test "supports where alias and except matchers" do
      query = from(post in Post)

      assert {:error, [%Issue{}]} =
               ExplicitVisibilityPredicates.validate(:all, query,
                 rules: [[where: [table: "posts"], fields: [:deleted_at]]]
               )

      assert :ok =
               ExplicitVisibilityPredicates.validate(:all, query,
                 rules: [
                   [
                     where: [table: "posts"],
                     except: [ecto_schema: Post],
                     fields: [:deleted_at]
                   ]
                 ]
               )
    end

    test "raises for invalid rule fields" do
      query = from(post in Post)

      assert_raise ArgumentError, "missing required :fields option", fn ->
        ExplicitVisibilityPredicates.validate(:all, query, rules: [[only: [ecto_schema: Post]]])
      end

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: []",
                   fn ->
                     ExplicitVisibilityPredicates.validate(:all, query,
                       rules: [[only: [ecto_schema: Post], fields: []]]
                     )
                   end
    end

    test "raises when old schemas shorthand is mixed with rules" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown option: :schemas", fn ->
        ExplicitVisibilityPredicates.validate(:all, query,
          schemas: [{Post, fields: [:deleted_at]}],
          rules: [[fields: [:status]]]
        )
      end
    end
  end

  defp opts do
    [
      schemas: [
        {Post, fields: [:deleted_at, :status]}
      ]
    ]
  end

  defp combination_queries(left_query, right_query) do
    [
      {:union, union(left_query, ^right_query)},
      {:union_all, union_all(left_query, ^right_query)},
      {:except, except(left_query, ^right_query)},
      {:except_all, except_all(left_query, ^right_query)},
      {:intersect, intersect(left_query, ^right_query)},
      {:intersect_all, intersect_all(left_query, ^right_query)}
    ]
  end
end
