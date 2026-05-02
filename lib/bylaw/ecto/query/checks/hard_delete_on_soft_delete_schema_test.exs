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

      assert {:error, %Issue{} = issue} =
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

      assert {:error, %Issue{} = issue} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.meta.root_schema == ArchivedPost
      assert issue.meta.soft_delete_fields == [:archived_at]
    end

    test "reports every reflected soft-delete field on the root schema" do
      query = from(post in LifecyclePost)

      assert {:error, %Issue{} = issue} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])

      assert issue.meta.soft_delete_fields == [:deleted_at, :archived_at]
    end

    test "returns an issue even when delete_all has root where predicates" do
      query =
        from(post in DeletedPost,
          where: is_nil(post.deleted_at) and post.status == ^"archived"
        )

      assert {:error, %Issue{} = issue} =
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

    test "passes when deleted_at is virtual" do
      query = from(post in VirtualDeletedPost)

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes for schema-less delete_all queries" do
      query = from(post in "posts")

      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, query, [])
    end

    test "passes for non-query values" do
      assert :ok = HardDeleteOnSoftDeleteSchema.validate(:delete_all, :not_a_query, [])
    end

    test "passes for non-delete operations on soft-delete schemas" do
      query = from(post in DeletedPost)

      Enum.each(@prepare_query_operations -- [:delete_all], fn operation ->
        assert :ok = HardDeleteOnSoftDeleteSchema.validate(operation, query, [])
      end)
    end

    test "respects the explicit query-level escape hatch" do
      query = from(post in DeletedPost)

      assert :ok =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query,
                 hard_delete_on_soft_delete_schema: [validate: false]
               )
    end

    test "validates when validate is explicitly true" do
      query = from(post in DeletedPost)

      assert {:error, %Issue{}} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query,
                 hard_delete_on_soft_delete_schema: [validate: true]
               )
    end

    test "requires an explicit false escape hatch" do
      query = from(post in DeletedPost)

      assert {:error, %Issue{}} =
               HardDeleteOnSoftDeleteSchema.validate(:delete_all, query,
                 hard_delete_on_soft_delete_schema: [validate: nil]
               )
    end

    test "raises when unsupported options are configured" do
      query = from(post in DeletedPost)

      assert_raise ArgumentError,
                   "unknown :hard_delete_on_soft_delete_schema option: :fields",
                   fn ->
                     HardDeleteOnSoftDeleteSchema.validate(:delete_all, query,
                       hard_delete_on_soft_delete_schema: [fields: [:deleted_at]]
                     )
                   end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in DeletedPost)

      assert_raise ArgumentError,
                   "expected :hard_delete_on_soft_delete_schema opts to be a keyword list, got: :bad",
                   fn ->
                     HardDeleteOnSoftDeleteSchema.validate(:delete_all, query,
                       hard_delete_on_soft_delete_schema: :bad
                     )
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in DeletedPost)

      assert_raise ArgumentError,
                   "expected :hard_delete_on_soft_delete_schema opts to be a keyword list, got: [:bad]",
                   fn ->
                     HardDeleteOnSoftDeleteSchema.validate(:delete_all, query,
                       hard_delete_on_soft_delete_schema: [:bad]
                     )
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
end
