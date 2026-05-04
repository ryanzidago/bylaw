defmodule Bylaw.Ecto.Query.Checks.HardDeleteOnSoftDeleteSchemaTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.HardDeleteOnSoftDeleteSchema
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule DeletedPost do
    use Ecto.Schema

    schema "deleted_posts" do
      field(:deleted_at, :utc_datetime)
      field(:status, :string)
      field(:title, :string)
    end
  end

  defmodule ArchivedPost do
    use Ecto.Schema

    schema "archived_posts" do
      field(:archived_at, :utc_datetime)
      field(:status, :string)
    end
  end

  defmodule LifecyclePost do
    use Ecto.Schema

    schema "lifecycle_posts" do
      field(:deleted_at, :utc_datetime)
      field(:archived_at, :utc_datetime)
      field(:status, :string)
    end
  end

  defmodule StringDeletedPost do
    use Ecto.Schema

    schema "string_deleted_posts" do
      field(:deleted_at, :string)
      field(:status, :string)
    end
  end

  defmodule PlainPost do
    use Ecto.Schema

    schema "plain_posts" do
      field(:status, :string)
      field(:title, :string)
    end
  end

  defmodule VirtualDeletedPost do
    use Ecto.Schema

    schema "virtual_deleted_posts" do
      field(:deleted_at, :utc_datetime, virtual: true)
      field(:status, :string)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:deleted_at, :utc_datetime)
      field(:post_id, :integer)
    end
  end

  describe "validate/3" do
    test "returns an issue when delete_all targets a schema with deleted_at" do
      query = from(post in DeletedPost)

      assert {:error, [%Issue{} = issue]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.check == HardDeleteOnSoftDeleteSchema

      assert issue.message ==
               "expected delete_all on schema with soft-delete fields to use update_all instead"

      assert issue.meta.operation == :delete_all
      assert issue.meta.root_schema == DeletedPost
      assert issue.meta.soft_delete_fields == [:deleted_at]
    end

    test "returns an issue when delete_all targets a schema with archived_at" do
      query = from(post in ArchivedPost)

      assert {:error, [%Issue{} = issue]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.meta.root_schema == ArchivedPost
      assert issue.meta.soft_delete_fields == [:archived_at]
    end

    test "reports every reflected soft-delete field on the root schema" do
      query = from(post in LifecyclePost)

      assert {:error, [%Issue{} = issue]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.meta.soft_delete_fields == [:deleted_at, :archived_at]
    end

    test "returns an issue based on field presence regardless of field type" do
      query = from(post in StringDeletedPost)

      assert {:error, [%Issue{} = issue]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.meta.root_schema == StringDeletedPost
      assert issue.meta.soft_delete_fields == [:deleted_at]
    end

    test "returns an issue even when delete_all has root where predicates" do
      query =
        from(post in DeletedPost,
          where: is_nil(post.deleted_at) and post.status == ^"archived"
        )

      assert {:error, [%Issue{} = issue]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.meta.soft_delete_fields == [:deleted_at]
    end

    test "passes when delete_all targets a schema without soft-delete fields" do
      query = from(post in PlainPost)

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes when soft-delete fields only exist on joined schemas" do
      query =
        from(post in PlainPost,
          join: comment in Comment,
          on: comment.post_id == post.id and is_nil(comment.deleted_at)
        )

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes when soft-delete schemas only appear inside join subqueries" do
      deleted_posts =
        from(post in DeletedPost,
          where: is_nil(post.deleted_at),
          select: %{id: post.id}
        )

      query =
        from(post in PlainPost,
          join: deleted_post in subquery(deleted_posts),
          on: deleted_post.id == post.id
        )

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes when deleted_at is virtual" do
      query = from(post in VirtualDeletedPost)

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes for schema-less delete_all queries" do
      query = from(post in "posts")

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes source subqueries because only branch root schemas are reflected" do
      scoped_posts =
        from(post in DeletedPost,
          where: is_nil(post.deleted_at),
          select: post.id
        )

      query = from(post in subquery(scoped_posts), select: post.id)

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes when soft-delete schemas only appear inside CTE queries" do
      deleted_posts =
        from(post in DeletedPost,
          where: is_nil(post.deleted_at),
          select: %{id: post.id}
        )

      query =
        PlainPost
        |> with_cte("deleted_posts", as: ^deleted_posts)
        |> join(:inner, [post], deleted_post in "deleted_posts",
          on: field(deleted_post, :id) == post.id
        )

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes for non-query values" do
      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, :not_a_query, [])
    end

    test "passes supported raw query maps without root schema sources" do
      query = %{from: nil, wheres: [%{expr: true, op: :and, params: []}]}

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "returns an issue for supported raw query maps with soft-delete root schemas" do
      query = %{from: %{source: {"deleted_posts", DeletedPost}}}

      assert {:error, [%Issue{} = issue]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.meta.root_schema == DeletedPost
      assert issue.meta.soft_delete_fields == [:deleted_at]
    end

    test "passes for non-delete operations on soft-delete schemas" do
      query = from(post in DeletedPost)

      Enum.each(@prepare_query_operations -- [:delete_all], fn operation ->
        assert :ok = HardDeleteOnSoftDeleteSchema.validate(operation, query, [])
      end)
    end

    test "passes when every combination branch root schema lacks soft-delete fields" do
      scoped_posts =
        from(post in PlainPost,
          where: post.status == ^"published",
          select: post.id
        )

      other_scoped_posts =
        from(post in PlainPost,
          where: post.status == ^"archived",
          select: post.id
        )

      query = union_all(scoped_posts, ^other_scoped_posts)

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "returns an issue when a combination branch root schema has soft-delete fields" do
      plain_posts =
        from(post in PlainPost,
          where: post.status == ^"published",
          select: post.id
        )

      deleted_posts =
        from(post in DeletedPost,
          where: is_nil(post.deleted_at),
          select: post.id
        )

      plain_posts
      |> combination_queries(deleted_posts)
      |> Enum.each(fn {operation, query} ->
        assert {:error, [%Issue{} = issue]} =
                 HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

        assert issue.meta.root_schema == DeletedPost
        assert issue.meta.soft_delete_fields == [:deleted_at]
        assert issue.meta.combination_path == [%{operation: operation, index: 0}]
      end)
    end

    test "returns every issue when the root and a combination branch have soft-delete fields" do
      deleted_posts =
        from(post in DeletedPost,
          where: is_nil(post.deleted_at),
          select: post.id
        )

      archived_posts =
        from(post in ArchivedPost,
          where: is_nil(post.archived_at),
          select: post.id
        )

      query = union_all(deleted_posts, ^archived_posts)

      assert {:error, [%Issue{} = root_issue, %Issue{} = combination_issue]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert root_issue.meta.root_schema == DeletedPost
      assert root_issue.meta.soft_delete_fields == [:deleted_at]
      refute Map.has_key?(root_issue.meta, :combination_path)

      assert combination_issue.meta.root_schema == ArchivedPost
      assert combination_issue.meta.soft_delete_fields == [:archived_at]
      assert combination_issue.meta.combination_path == [%{operation: :union_all, index: 0}]
    end

    test "tracks nested combination branches with soft-delete root schemas" do
      plain_posts =
        from(post in PlainPost,
          where: post.status == ^"published",
          select: post.id
        )

      other_plain_posts =
        from(post in PlainPost,
          where: post.status == ^"archived",
          select: post.id
        )

      deleted_posts =
        from(post in DeletedPost,
          where: is_nil(post.deleted_at),
          select: post.id
        )

      nested_query = union_all(other_plain_posts, ^deleted_posts)
      query = union(plain_posts, ^nested_query)

      assert {:error, [%Issue{} = issue]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.meta.root_schema == DeletedPost
      assert issue.meta.soft_delete_fields == [:deleted_at]

      assert issue.meta.combination_path == [
               %{operation: :union, index: 0},
               %{operation: :union_all, index: 0}
             ]
    end

    test "respects the explicit validate false option" do
      query = from(post in DeletedPost)

      assert :ok =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, validate: false)
    end

    test "validates when validate is explicitly true" do
      query = from(post in DeletedPost)

      assert {:error, [%Issue{}]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, validate: true)
    end

    test "requires an explicit false validate option" do
      query = from(post in DeletedPost)

      assert {:error, [%Issue{}]} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, validate: nil)
    end

    test "raises when unsupported options are configured" do
      query = from(post in DeletedPost)

      assert_raise ArgumentError,
                   "unknown option: :fields",
                   fn ->
                     HardDeleteOnSoftDeleteSchema.validate(:delete_all, query,
                       fields: [:deleted_at]
                     )
                   end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in DeletedPost)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: :bad",
                   fn ->
                     HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in DeletedPost)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [:bad]",
                   fn ->
                     HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [:bad])
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in DeletedPost)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :bad", fn ->
        HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, :bad)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in DeletedPost)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:bad]", fn ->
        HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [:bad])
      end
    end
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
