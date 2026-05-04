defmodule Bylaw.Ecto.Query.Checks.EmptyInPredicatesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.EmptyInPredicates
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:integer_status, Ecto.Enum, values: [draft: 1, published: 2, archived: 3])
      field(:published_at, :utc_datetime)
      field(:sequence, :integer)
      field(:status, Ecto.Enum, values: [:draft, :published, :archived])
      field(:title, :string)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:status, Ecto.Enum, values: [:draft, :published, :archived])
    end
  end

  describe "validate/3" do
    test "passes when there are no where predicates" do
      query = from(post in Post)

      assert :ok = EmptyInPredicates.validate(:all, query, [])
    end

    test "returns an issue when a pinned in predicate list is empty" do
      ids = []
      query = from(post in Post, where: post.id in ^ids)

      assert {:error, [%Issue{} = issue]} = EmptyInPredicates.validate(:all, query, [])

      assert issue.check == EmptyInPredicates
      assert issue.message == "expected in predicate on :id to include at least one non-nil value"
      assert issue.meta.operation == :all
      assert issue.meta.field == :id
      assert issue.meta.predicates == [%{operator: :in, values: []}]
    end

    test "returns an issue for every Ecto prepare_query operation" do
      query = from(post in Post, where: post.id in ^[])

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, [%Issue{} = issue]} = EmptyInPredicates.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.field == :id
      end)
    end

    test "returns an issue when a literal in predicate list is empty" do
      query = from(post in Post, where: post.sequence in [])

      assert {:error, [%Issue{} = issue]} = EmptyInPredicates.validate(:all, query, [])

      assert issue.meta.field == :sequence
      assert issue.meta.predicates == [%{operator: :in, values: []}]
    end

    test "returns an issue when an in predicate only contains nil values" do
      query = from(post in Post, where: post.status in ^[nil])

      assert {:error, [%Issue{} = issue]} = EmptyInPredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert issue.meta.predicates == [%{operator: :in, values: []}]
    end

    test "returns an issue for empty in predicates on supported raw query AST" do
      query =
        query_with_expr(
          {:in, [], [root_field(:published_at), {:^, [], [0]}]},
          [{[], {:array, :utc_datetime}}]
        )

      assert {:error, [%Issue{} = issue]} = EmptyInPredicates.validate(:all, query, [])

      assert issue.meta.field == :published_at
      assert issue.meta.predicates == [%{operator: :in, values: []}]
    end

    test "returns an issue when an empty in predicate uses named root field expressions" do
      query =
        from(post in Post,
          as: :post,
          where: field(as(:post), :status) in ^[]
        )

      assert {:error, [%Issue{} = issue]} = EmptyInPredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert issue.meta.predicates == [%{operator: :in, values: []}]
    end

    test "passes when an in predicate has at least one non-nil value" do
      query = from(post in Post, where: post.id in ^[1, nil])

      assert :ok = EmptyInPredicates.validate(:all, query, [])
    end

    test "ignores invalid enum values because Ecto will reject them separately" do
      query = from(post in Post, where: post.status in ^["not-a-status"])

      assert :ok = EmptyInPredicates.validate(:all, query, [])
    end

    test "ignores empty in predicates on non-root bindings" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: comment.status in ^[]
        )

      assert :ok = EmptyInPredicates.validate(:all, query, [])
    end

    test "passes when an or branch can still return rows" do
      query = from(post in Post, where: post.id in ^[] or post.status == :draft)

      assert :ok = EmptyInPredicates.validate(:all, query, [])
    end

    test "returns issues when every or branch contains an empty in predicate" do
      query = from(post in Post, where: post.id in ^[] or post.status in ^[])

      assert {:error, [%Issue{} = first_issue, %Issue{} = second_issue]} =
               EmptyInPredicates.validate(:all, query, [])

      assert first_issue.meta.field == :id
      assert second_issue.meta.field == :status
    end

    test "passes for schema-less sources" do
      query = from(post in "posts", where: field(post, :id) in ^[])

      assert :ok = EmptyInPredicates.validate(:all, query, [])
    end

    test "respects the explicit validate false option" do
      query = from(post in Post, where: post.id in ^[])

      assert :ok = EmptyInPredicates.validate(:all, query, validate: false)
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post, where: post.id in ^[])

      assert {:error, [%Issue{} = issue]} =
               EmptyInPredicates.validate(:all, query, validate: true)

      assert issue.meta.field == :id
    end

    test "requires an explicit false validate option" do
      query = from(post in Post, where: post.id in ^[])

      assert {:error, [%Issue{}]} = EmptyInPredicates.validate(:all, query, validate: nil)
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown option: :fields", fn ->
        EmptyInPredicates.validate(:all, query, fields: [:status])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: :bad",
                   fn ->
                     EmptyInPredicates.validate(:all, query, :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [true]",
                   fn ->
                     EmptyInPredicates.validate(:all, query, [true])
                   end
    end
  end

  defp query_with_expr(expr, params) do
    %{
      aliases: %{},
      from: %{source: {"posts", Post}},
      wheres: [
        %{
          expr: expr,
          op: :and,
          params: params
        }
      ]
    }
  end

  defp root_field(field), do: {{:., [], [{:&, [], [0]}, field]}, [], []}
end
