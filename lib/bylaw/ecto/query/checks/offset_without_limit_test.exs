defmodule Bylaw.Ecto.Query.Checks.OffsetWithoutLimitTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.OffsetWithoutLimit
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
    end
  end

  describe "validate/3" do
    test "passes when a query has no offset" do
      query = from(post in Post)

      assert :ok = OffsetWithoutLimit.validate(:all, query, [])
    end

    test "passes when a query has limit without offset" do
      query = from(post in Post, limit: 10)

      assert :ok = OffsetWithoutLimit.validate(:all, query, [])
    end

    test "passes when offset is bounded by limit" do
      query = from(post in Post, limit: 10, offset: 50)

      assert :ok = OffsetWithoutLimit.validate(:all, query, [])
    end

    test "passes when offset is bounded by limit through query composition" do
      query =
        Post
        |> offset(50)
        |> limit(10)

      assert :ok = OffsetWithoutLimit.validate(:all, query, [])
    end

    test "returns an issue when offset has no limit" do
      query = from(post in Post, offset: 50)

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.check == OffsetWithoutLimit
      assert issue.message == "expected query with offset to include limit"
      assert issue.meta.operation == :all
      assert issue.meta.reason == :offset_without_limit
    end

    test "returns an issue when offset is added through query composition" do
      query = offset(Post, 50)

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.check == OffsetWithoutLimit
      assert issue.meta.reason == :offset_without_limit
    end

    test "returns an issue when an ordered query has offset and no limit" do
      query = from(post in Post, order_by: post.title, offset: 50)

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.check == OffsetWithoutLimit
      assert issue.message == "expected query with offset to include limit"
    end

    test "returns an issue for every Ecto prepare_query operation" do
      query = from(post in Post, offset: 50)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(operation, query, [])

        assert issue.check == OffsetWithoutLimit
        assert issue.meta.operation == operation
        assert issue.meta.reason == :offset_without_limit
      end)
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok = OffsetWithoutLimit.validate(:all, :not_a_query, [])
    end

    test "returns an issue when a schema-less query has offset and no limit" do
      query = from(post in "posts", offset: 50)

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.check == OffsetWithoutLimit
      assert issue.meta.reason == :offset_without_limit
    end

    test "passes for Ecto exists query rewrites that preserve offset" do
      query =
        Post
        |> offset(50)
        |> exclude(:select)
        |> exclude(:preload)
        |> exclude(:order_by)
        |> exclude(:distinct)
        |> select(1)
        |> limit(1)

      assert :ok = OffsetWithoutLimit.validate(:all, query, [])
    end

    test "passes supported raw query maps with offset bounded by limit" do
      query = %{offset: %{expr: 50}, limit: %{expr: 10}}

      assert :ok = OffsetWithoutLimit.validate(:all, query, [])
    end

    test "returns an issue for supported raw query maps with offset and no limit" do
      query = %{offset: %{expr: 50}}

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.check == OffsetWithoutLimit
      assert issue.meta.reason == :offset_without_limit
    end

    test "returns an issue when a source subquery has offset and no limit" do
      offset_posts = from(post in Post, offset: 10)
      query = from(post in subquery(offset_posts), select: count())

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.message == "expected query with offset to include limit"
      assert issue.meta.reason == :offset_without_limit
    end

    test "passes when a source subquery has offset bounded by limit" do
      offset_posts = from(post in Post, limit: 10, offset: 10)
      query = from(post in subquery(offset_posts), select: count())

      assert :ok = OffsetWithoutLimit.validate(:all, query, [])
    end

    test "returns an issue when a join subquery has offset and no limit" do
      offset_posts = from(post in Post, offset: 10)

      query =
        from(post in Post,
          join: offset_post in subquery(offset_posts),
          on: offset_post.id == post.id
        )

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.message == "expected query with offset to include limit"
    end

    test "returns an issue when a CTE query has offset and no limit" do
      offset_posts = from(post in Post, offset: 10)

      query =
        Post
        |> with_cte("offset_posts", as: ^offset_posts)
        |> join(:inner, [post], offset_post in "offset_posts",
          on: field(offset_post, :id) == post.id
        )

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.message == "expected query with offset to include limit"
    end

    test "returns an issue when a combination query has offset and no limit" do
      offset_posts = from(post in Post, select: post.id, offset: 10)

      query =
        Post
        |> select([post], post.id)
        |> union_all(^offset_posts)

      assert {:error, %Issue{} = issue} = OffsetWithoutLimit.validate(:all, query, [])

      assert issue.message == "expected query with offset to include limit"
    end

    test "respects the explicit query-level escape hatch" do
      query = from(post in Post, offset: 10)

      assert :ok =
               OffsetWithoutLimit.validate(:all, query, offset_without_limit: [validate: false])
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post, offset: 10)

      assert {:error, %Issue{}} =
               OffsetWithoutLimit.validate(:all, query, offset_without_limit: [validate: true])
    end

    test "requires an explicit false escape hatch" do
      query = from(post in Post, offset: 10)

      assert {:error, %Issue{}} =
               OffsetWithoutLimit.validate(:all, query, offset_without_limit: [validate: nil])
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post, offset: 10)

      assert_raise ArgumentError, "unknown :offset_without_limit option: :allow", fn ->
        OffsetWithoutLimit.validate(:all, query, offset_without_limit: [allow: true])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post, offset: 10)

      assert_raise ArgumentError,
                   "expected :offset_without_limit opts to be a keyword list, got: :bad",
                   fn ->
                     OffsetWithoutLimit.validate(:all, query, offset_without_limit: :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post, offset: 10)

      assert_raise ArgumentError,
                   "expected :offset_without_limit opts to be a keyword list, got: [:bad]",
                   fn ->
                     OffsetWithoutLimit.validate(:all, query, offset_without_limit: [:bad])
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post, offset: 10)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :bad", fn ->
        OffsetWithoutLimit.validate(:all, query, :bad)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post, offset: 10)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:bad]", fn ->
        OffsetWithoutLimit.validate(:all, query, [:bad])
      end
    end
  end
end
