defmodule Bylaw.Ecto.Query.Checks.UnboundedDeletesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.UnboundedDeletes
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
      field(:status, :string)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:post_id, :integer)
    end
  end

  describe "validate/3" do
    test "returns an issue when delete_all has no where clause" do
      query = from(post in Post)

      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, query, [])

      assert issue.check == UnboundedDeletes
      assert issue.message == "expected delete_all query to include at least one where clause"
      assert issue.meta.operation == :delete_all
    end

    test "returns an issue when delete_all only has a literal true where clause" do
      query = from(post in Post, where: true)

      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, query, [])

      assert issue.check == UnboundedDeletes
      assert issue.meta.operation == :delete_all
    end

    test "returns an issue when delete_all has an empty keyword where clause" do
      query = from(Post, where: [])

      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, query, [])

      assert issue.check == UnboundedDeletes
      assert issue.meta.operation == :delete_all
    end

    test "passes when delete_all has a where clause" do
      query = from(post in Post, where: post.status == ^"archived")

      assert :ok = UnboundedDeletes.validate(:delete_all, query, [])
    end

    test "passes when delete_all has a keyword where clause" do
      query = from(Post, where: [status: "archived"])

      assert :ok = UnboundedDeletes.validate(:delete_all, query, [])
    end

    test "passes when delete_all has a dynamic where expression" do
      status = "archived"
      predicate = dynamic([post], post.status == ^status)
      query = from(post in Post, where: ^predicate)

      assert :ok = UnboundedDeletes.validate(:delete_all, query, [])
    end

    test "passes when a schema-less delete_all query has a where clause" do
      query = from(post in "posts", where: field(post, :status) == "archived")

      assert :ok = UnboundedDeletes.validate(:delete_all, query, [])
    end

    test "passes when delete_all has an or_where clause" do
      query = from(post in Post, or_where: post.status == ^"archived")

      assert :ok = UnboundedDeletes.validate(:delete_all, query, [])
    end

    test "passes when delete_all has a where clause added through composition" do
      query = where(Post, [post], post.status == "archived")

      assert :ok = UnboundedDeletes.validate(:delete_all, query, [])
    end

    test "does not count join predicates as a where clause" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, query, [])

      assert issue.check == UnboundedDeletes
    end

    test "does not count source subquery predicates as a root where clause" do
      scoped_posts = from(post in Post, where: post.status == ^"archived")
      query = from(post in subquery(scoped_posts), select: post.id)

      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, query, [])

      assert issue.check == UnboundedDeletes
      assert issue.meta.operation == :delete_all
    end

    test "does not count CTE predicates as a root where clause" do
      scoped_posts = from(post in Post, where: post.status == ^"archived")
      query = with_cte(Post, "scoped_posts", as: ^scoped_posts)

      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, query, [])

      assert issue.check == UnboundedDeletes
      assert issue.meta.operation == :delete_all
    end

    test "passes for non-delete operations without where clauses" do
      query = from(post in Post)

      Enum.each(@prepare_query_operations -- [:delete_all], fn operation ->
        assert :ok = UnboundedDeletes.validate(operation, query, [])
      end)
    end

    test "returns an issue when delete_all cannot find where clauses on a non-query value" do
      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, :not_a_query, [])

      assert issue.check == UnboundedDeletes
      assert issue.meta.operation == :delete_all
    end

    test "passes supported raw query maps with where entries" do
      query = %{wheres: [%{expr: {:==, [], [1, 1]}, op: :and, params: []}]}

      assert :ok = UnboundedDeletes.validate(:delete_all, query, [])
    end

    test "returns an issue for supported raw query maps with literal true where entries" do
      query = %{wheres: [%{expr: true, op: :and, params: []}]}

      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, query, [])

      assert issue.check == UnboundedDeletes
      assert issue.meta.operation == :delete_all
    end

    test "returns an issue for supported raw query maps without where entries" do
      query = %{wheres: []}

      assert {:error, %Issue{} = issue} = UnboundedDeletes.validate(:delete_all, query, [])

      assert issue.check == UnboundedDeletes
      assert issue.meta.operation == :delete_all
    end

    test "respects the explicit query-level escape hatch" do
      query = from(post in Post)

      assert :ok =
               UnboundedDeletes.validate(:delete_all, query, unbounded_deletes: [validate: false])
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post)

      assert {:error, %Issue{}} =
               UnboundedDeletes.validate(:delete_all, query, unbounded_deletes: [validate: true])
    end

    test "requires an explicit false escape hatch" do
      query = from(post in Post)

      assert {:error, %Issue{}} =
               UnboundedDeletes.validate(:delete_all, query, unbounded_deletes: [validate: nil])
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown :unbounded_deletes option: :mode", fn ->
        UnboundedDeletes.validate(:delete_all, query, unbounded_deletes: [mode: :strict])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :unbounded_deletes opts to be a keyword list, got: :bad",
                   fn ->
                     UnboundedDeletes.validate(:delete_all, query, unbounded_deletes: :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :unbounded_deletes opts to be a keyword list, got: [:bad]",
                   fn ->
                     UnboundedDeletes.validate(:delete_all, query, unbounded_deletes: [:bad])
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :bad", fn ->
        UnboundedDeletes.validate(:delete_all, query, :bad)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:bad]", fn ->
        UnboundedDeletes.validate(:delete_all, query, [:bad])
      end
    end
  end
end
