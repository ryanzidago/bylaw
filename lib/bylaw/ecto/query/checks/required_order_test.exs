defmodule Bylaw.Ecto.Query.Checks.RequiredOrderTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.DeterministicOrder
  alias Bylaw.Ecto.Query.Checks.RequiredOrder
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
    end
  end

  describe "validate/3" do
    test "passes when an unordered query shape does not require ordering" do
      query = from(post in Post)

      assert :ok = RequiredOrder.validate(:all, query, [])
    end

    test "returns an issue when limit has no order_by" do
      query = from(post in Post, limit: 10)

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.check == RequiredOrder
      assert issue.message == "expected query with limit to include order_by"
      assert issue.meta.operation == :all
      assert issue.meta.required_by == [:limit]
    end

    test "returns an issue when offset has no order_by" do
      query = from(post in Post, offset: 50)

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.check == RequiredOrder
      assert issue.message == "expected query with offset to include order_by"
      assert issue.meta.required_by == [:offset]
    end

    test "returns every reason that requires ordering" do
      query = from(post in Post, limit: 10, offset: 50)

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:stream, query, [])

      assert issue.message ==
               "expected query with limit, offset, stream operation to include order_by"

      assert issue.meta.operation == :stream
      assert issue.meta.required_by == [:limit, :offset, :stream]
    end

    test "returns an issue when stream has no order_by" do
      query = from(post in Post)

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:stream, query, [])

      assert issue.check == RequiredOrder
      assert issue.message == "expected query with stream operation to include order_by"
      assert issue.meta.operation == :stream
      assert issue.meta.required_by == [:stream]
    end

    test "returns an issue when stream cannot find order_by on a non-query value" do
      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:stream, :not_a_query, [])

      assert issue.check == RequiredOrder
      assert issue.meta.operation == :stream
      assert issue.meta.required_by == [:stream]
    end

    test "returns an issue for every Ecto prepare_query operation when limit has no order_by" do
      query = from(post in Post, limit: 10)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} = RequiredOrder.validate(operation, query, [])

        assert issue.check == RequiredOrder
        assert issue.meta.operation == operation

        if operation == :stream do
          assert issue.meta.required_by == [:limit, :stream]
        else
          assert issue.meta.required_by == [:limit]
        end
      end)
    end

    test "passes for every Ecto prepare_query operation when required ordering exists" do
      query = from(post in Post, order_by: post.title, limit: 10)

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok = RequiredOrder.validate(operation, query, [])
      end)
    end

    test "passes when limit has any order_by" do
      query = from(post in Post, order_by: post.title, limit: 10)

      assert :ok = RequiredOrder.validate(:all, query, [])
    end

    test "returns an issue when limit has an empty order_by" do
      query = from(post in Post, order_by: [], limit: 10)

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.check == RequiredOrder
      assert issue.message == "expected query with limit to include order_by"
      assert issue.meta.required_by == [:limit]
    end

    test "returns an issue when limit has an empty interpolated order_by" do
      order_by = []
      query = from(post in Post, order_by: ^order_by, limit: 10)

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.check == RequiredOrder
      assert issue.message == "expected query with limit to include order_by"
      assert issue.meta.required_by == [:limit]
    end

    test "passes when offset has any order_by" do
      query = from(post in Post, order_by: post.title, offset: 50)

      assert :ok = RequiredOrder.validate(:all, query, [])
    end

    test "passes when stream has any order_by" do
      query = from(post in Post, order_by: post.title)

      assert :ok = RequiredOrder.validate(:stream, query, [])
    end

    test "passes for Ecto exists query rewrites" do
      query =
        Post
        |> exclude(:select)
        |> exclude(:preload)
        |> exclude(:order_by)
        |> exclude(:distinct)
        |> select(1)
        |> limit(1)

      assert :ok = RequiredOrder.validate(:all, query, [])
    end

    test "returns an issue when an Ecto exists query rewrite preserves offset" do
      query =
        Post
        |> offset(50)
        |> exclude(:select)
        |> exclude(:preload)
        |> exclude(:order_by)
        |> exclude(:distinct)
        |> select(1)
        |> limit(1)

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.check == RequiredOrder
      assert issue.message == "expected query with offset to include order_by"
      assert issue.meta.required_by == [:offset]
    end

    test "returns an issue when a source subquery has limit and no order_by" do
      limited_posts = from(post in Post, limit: 10)
      query = from(post in subquery(limited_posts), select: count())

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.message == "expected query with limit to include order_by"
      assert issue.meta.required_by == [:limit]
    end

    test "returns an issue when a source subquery has offset and no order_by" do
      offset_posts = from(post in Post, offset: 10)
      query = from(post in subquery(offset_posts), select: count())

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.message == "expected query with offset to include order_by"
      assert issue.meta.required_by == [:offset]
    end

    test "returns an issue when a join subquery has limit and no order_by" do
      limited_posts = from(post in Post, limit: 10)

      query =
        from(post in Post,
          join: limited_post in subquery(limited_posts),
          on: limited_post.id == post.id
        )

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.message == "expected query with limit to include order_by"
      assert issue.meta.required_by == [:limit]
    end

    test "passes when a join subquery with limit has order_by" do
      limited_posts = from(post in Post, order_by: post.title, limit: 10)

      query =
        from(post in Post,
          join: limited_post in subquery(limited_posts),
          on: limited_post.id == post.id
        )

      assert :ok = RequiredOrder.validate(:all, query, [])
    end

    test "returns an issue when a CTE query has limit and no order_by" do
      limited_posts = from(post in Post, limit: 10)

      query =
        Post
        |> with_cte("limited_posts", as: ^limited_posts)
        |> join(:inner, [post], limited_post in "limited_posts",
          on: field(limited_post, :id) == post.id
        )

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.message == "expected query with limit to include order_by"
      assert issue.meta.required_by == [:limit]
    end

    test "passes when a CTE query with limit has order_by" do
      limited_posts = from(post in Post, order_by: post.title, limit: 10)

      query =
        Post
        |> with_cte("limited_posts", as: ^limited_posts)
        |> join(:inner, [post], limited_post in "limited_posts",
          on: field(limited_post, :id) == post.id
        )

      assert :ok = RequiredOrder.validate(:all, query, [])
    end

    test "returns an issue when a combination query has limit and no order_by" do
      limited_posts = from(post in Post, select: post.id, limit: 10)

      query =
        Post
        |> select([post], post.id)
        |> union_all(^limited_posts)

      assert {:error, %Issue{} = issue} = RequiredOrder.validate(:all, query, [])

      assert issue.message == "expected query with limit to include order_by"
      assert issue.meta.required_by == [:limit]
    end

    test "passes when a combination query with limit has order_by" do
      limited_posts = from(post in Post, select: post.id, order_by: post.title, limit: 10)

      query =
        Post
        |> select([post], post.id)
        |> union_all(^limited_posts)

      assert :ok = RequiredOrder.validate(:all, query, [])
    end

    test "passes when Ecto.Query.first/2 and last/2 provide order_by" do
      assert :ok = RequiredOrder.validate(:all, first(Post), [])
      assert :ok = RequiredOrder.validate(:all, last(Post), [])
    end

    test "matches the required order and deterministic order failure matrix" do
      unordered_query = from(post in Post)
      ordered_query = from(post in Post, order_by: post.title)
      bounded_query = from(post in Post, limit: 10)
      bounded_ordered_query = from(post in Post, order_by: post.title, limit: 10)

      deterministic_bounded_query =
        from(post in Post, order_by: [asc: post.title, asc: post.id], limit: 10)

      assert :ok = RequiredOrder.validate(:all, unordered_query, [])
      assert :ok = DeterministicOrder.validate(:all, unordered_query, [])

      assert :ok = RequiredOrder.validate(:all, ordered_query, [])

      assert {:error, %Issue{check: DeterministicOrder}} =
               DeterministicOrder.validate(:all, ordered_query, [])

      assert {:error, %Issue{check: RequiredOrder}} =
               RequiredOrder.validate(:all, bounded_query, [])

      assert :ok = DeterministicOrder.validate(:all, bounded_query, [])

      assert :ok = RequiredOrder.validate(:all, bounded_ordered_query, [])

      assert {:error, %Issue{check: DeterministicOrder}} =
               DeterministicOrder.validate(:all, bounded_ordered_query, [])

      assert :ok = RequiredOrder.validate(:all, deterministic_bounded_query, [])
      assert :ok = DeterministicOrder.validate(:all, deterministic_bounded_query, [])
    end

    test "respects the explicit query-level escape hatch" do
      query = from(post in Post, limit: 10)

      assert :ok = RequiredOrder.validate(:all, query, required_order: [validate: false])
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post, limit: 10)

      assert {:error, %Issue{}} =
               RequiredOrder.validate(:all, query, required_order: [validate: true])
    end

    test "requires an explicit false escape hatch" do
      query = from(post in Post, limit: 10)

      assert {:error, %Issue{}} =
               RequiredOrder.validate(:all, query, required_order: [validate: nil])
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post, limit: 10)

      assert_raise ArgumentError, "unknown :required_order option: :reasons", fn ->
        RequiredOrder.validate(:all, query, required_order: [reasons: [:limit]])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post, limit: 10)

      assert_raise ArgumentError,
                   "expected :required_order opts to be a keyword list, got: :bad",
                   fn ->
                     RequiredOrder.validate(:all, query, required_order: :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post, limit: 10)

      assert_raise ArgumentError,
                   "expected :required_order opts to be a keyword list, got: [:bad]",
                   fn ->
                     RequiredOrder.validate(:all, query, required_order: [:bad])
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post, limit: 10)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :bad", fn ->
        RequiredOrder.validate(:all, query, :bad)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post, limit: 10)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:bad]", fn ->
        RequiredOrder.validate(:all, query, [:bad])
      end
    end
  end
end
