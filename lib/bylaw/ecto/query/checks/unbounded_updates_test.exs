defmodule Bylaw.Ecto.Query.Checks.UnboundedUpdatesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.UnboundedUpdates
  alias Bylaw.Ecto.Query.Issue

  @non_update_operations [:all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:published, :boolean)
      field(:title, :string)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:post_id, :integer)
      field(:body, :string)
    end
  end

  describe "validate/3" do
    test "passes when an update_all query has a where clause" do
      query = from(post in Post, where: post.title == ^"draft")

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "passes when an update_all query has a keyword where clause" do
      query = from(Post, where: [published: false])

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "passes when an update_all query has a dynamic where expression" do
      published = false
      predicate = dynamic([post], post.published == ^published)
      query = from(post in Post, where: ^predicate)

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "passes when an update_all query has an or_where clause" do
      query = from(post in Post, or_where: post.published == false)

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "passes when a schema-less update_all query has a where clause" do
      query = from(post in "posts", where: field(post, :published) == false)

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "passes when an update_all query has updates and a where clause" do
      query =
        from(post in Post,
          where: post.published == false,
          update: [set: [title: ^"Archived"]]
        )

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "passes when an update_all query has a where clause added through composition" do
      query =
        Post
        |> where([post], post.published == false)
        |> update([post], set: [title: post.title])

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "passes when an update_all query has joins and a where clause" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          where: post.published == false,
          update: [set: [title: ^"Archived"]]
        )

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "returns an issue when an update_all query has no where clause" do
      query = from(post in Post)

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.message == "expected update_all query to include at least one where clause"
      assert issue.meta.operation == :update_all
    end

    test "returns an issue when an update_all query has updates but no where clause" do
      query = from(post in Post, update: [set: [title: ^"Archived"]])

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "returns an issue when an update_all query only has a literal true where clause" do
      query = from(post in Post, where: true)

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "returns an issue when an update_all query has an empty keyword where clause" do
      query = from(Post, where: [])

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "returns an issue when an update_all query only has join predicates" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          update: [set: [title: ^"Archived"]]
        )

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "returns an issue when an update_all query cannot be inspected" do
      assert {:error, %Issue{} = issue} =
               UnboundedUpdates.validate(:update_all, :not_a_query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "passes supported raw query maps with where entries" do
      query = %{wheres: [%{expr: {:==, [], [1, 1]}, op: :and, params: []}]}

      assert :ok = UnboundedUpdates.validate(:update_all, query, [])
    end

    test "returns an issue for supported raw query maps with literal true where entries" do
      query = %{wheres: [%{expr: true, op: :and, params: []}]}

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "returns an issue for supported raw query maps without where entries" do
      query = %{wheres: []}

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "returns an issue for supported raw query maps with no wheres key" do
      query = %{}

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "returns an issue for supported raw query maps with malformed wheres" do
      query = %{wheres: :invalid}

      assert {:error, %Issue{} = issue} = UnboundedUpdates.validate(:update_all, query, [])

      assert issue.check == UnboundedUpdates
      assert issue.meta.operation == :update_all
    end

    test "passes for non-update operations without a where clause" do
      query = from(post in Post)

      Enum.each(@non_update_operations, fn operation ->
        assert :ok = UnboundedUpdates.validate(operation, query, [])
      end)
    end

    test "respects the explicit query-level escape hatch" do
      query = from(post in Post)

      assert :ok =
               UnboundedUpdates.validate(:update_all, query, unbounded_updates: [validate: false])
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post)

      assert {:error, %Issue{}} =
               UnboundedUpdates.validate(:update_all, query, unbounded_updates: [validate: true])
    end

    test "requires an explicit false escape hatch" do
      query = from(post in Post)

      assert {:error, %Issue{}} =
               UnboundedUpdates.validate(:update_all, query, unbounded_updates: [validate: nil])
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown :unbounded_updates option: :fields", fn ->
        UnboundedUpdates.validate(:update_all, query, unbounded_updates: [fields: [:id]])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :unbounded_updates opts to be a keyword list, got: :bad",
                   fn ->
                     UnboundedUpdates.validate(:update_all, query, unbounded_updates: :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :unbounded_updates opts to be a keyword list, got: [:bad]",
                   fn ->
                     UnboundedUpdates.validate(:update_all, query, unbounded_updates: [:bad])
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :bad", fn ->
        UnboundedUpdates.validate(:update_all, query, :bad)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:bad]", fn ->
        UnboundedUpdates.validate(:update_all, query, [:bad])
      end
    end
  end
end
