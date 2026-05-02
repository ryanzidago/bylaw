defmodule Bylaw.Ecto.Query.Checks.ConflictingWherePredicatesTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.ConflictingWherePredicates
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:integer_status, Ecto.Enum, values: [draft: 1, published: 2, archived: 3])
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

  defmodule PlainPost do
    use Ecto.Schema

    schema "plain_posts" do
      field(:status, :string)
    end
  end

  describe "validate/3" do
    test "passes when there are no where predicates" do
      query = from(post in Post)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "passes when repeated enum equality predicates agree" do
      status = :draft
      query = from(post in Post, where: post.status == ^status, where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "returns an issue when keyword where syntax conflicts" do
      next_status = :published
      query = from(post in Post, where: [status: :draft], where: [status: ^next_status])

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status

      assert issue.meta.predicates == [
               %{operator: :==, values: [:draft]},
               %{operator: :==, values: [:published]}
             ]
    end

    test "returns an issue when enum equality predicates conflict across where clauses" do
      current_status = :draft
      next_status = :published

      query =
        from(post in Post,
          where: post.status == ^current_status,
          where: post.status == ^next_status
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.check == ConflictingWherePredicates
      assert issue.message == "expected enum where predicates on :status to agree on a value"
      assert issue.meta.operation == :all
      assert issue.meta.field == :status
      assert issue.meta.enum_values == [:draft, :published, :archived]

      assert issue.meta.predicates == [
               %{operator: :==, values: [:draft]},
               %{operator: :==, values: [:published]}
             ]
    end

    test "returns an issue when enum equality predicates conflict inside one and expression" do
      query =
        from(post in Post,
          where: post.status == ^:draft and post.status == ^:published
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status

      assert issue.meta.predicates == [
               %{operator: :==, values: [:draft]},
               %{operator: :==, values: [:published]}
             ]
    end

    test "returns an issue when enum equality predicates conflict inside a dynamic expression" do
      status = :draft
      predicate = dynamic([post], post.status == ^status and post.status == ^:published)
      query = from(post in Post, where: ^predicate)

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status

      assert issue.meta.predicates == [
               %{operator: :==, values: [:draft]},
               %{operator: :==, values: [:published]}
             ]
    end

    test "returns an issue for every Ecto prepare_query operation when predicates conflict" do
      query = from(post in Post, where: post.status == :draft, where: post.status == :published)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} =
                 ConflictingWherePredicates.validate(operation, query, [])

        assert issue.meta.operation == operation
        assert issue.meta.field == :status
      end)
    end

    test "accepts enum equality predicates with the field on the right" do
      query = from(post in Post, where: ^:draft == post.status, where: post.status == :published)

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "returns an issue when enum predicates use field/2" do
      next_status = :published

      query =
        from(post in Post,
          where: field(post, :status) == :draft,
          where: field(post, :status) == ^next_status
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "accepts enum predicates from named root bindings" do
      query =
        from(post in Post,
          as: :post,
          where: as(:post).status == :draft,
          where: post.status == :published
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "accepts enum predicates from named root bindings with field/2" do
      query =
        from(post in Post,
          as: :post,
          where: field(as(:post), :status) == :draft,
          where: post.status == :published
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "passes when enum in and equality predicates overlap" do
      statuses = [:draft, :published]

      query =
        from(post in Post,
          where: post.status in ^statuses,
          where: post.status == ^:published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "passes when enum in predicates overlap" do
      statuses = [:published, :archived]

      query =
        from(post in Post,
          where: post.status in [:draft, :published],
          where: post.status in ^statuses
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "returns an issue when enum in and equality predicates are disjoint" do
      query =
        from(post in Post,
          where: post.status in [:draft, :published],
          where: post.status == ^:archived
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.predicates == [
               %{operator: :in, values: [:draft, :published]},
               %{operator: :==, values: [:archived]}
             ]
    end

    test "returns an issue when enum in predicates are disjoint" do
      query =
        from(post in Post,
          where: post.status in [:draft],
          where: post.status in ^[:published, :archived]
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.predicates == [
               %{operator: :in, values: [:draft]},
               %{operator: :in, values: [:archived, :published]}
             ]
    end

    test "returns an issue when enum in predicates use named root field expressions" do
      query =
        from(post in Post,
          as: :post,
          where: field(as(:post), :status) in [:draft],
          where: post.status == :published
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status

      assert issue.meta.predicates == [
               %{operator: :in, values: [:draft]},
               %{operator: :==, values: [:published]}
             ]
    end

    test "returns an issue when an enum in predicate has no possible values" do
      query = from(post in Post, where: post.status in ^[])

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert issue.meta.predicates == [%{operator: :in, values: []}]
    end

    test "ignores enum in predicates with invalid enum values" do
      query =
        from(post in Post,
          where: post.status in ["not-a-status"],
          where: post.status == :published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores pinned enum in predicates with invalid enum values" do
      statuses = ["not-a-status"]

      query =
        from(post in Post,
          where: post.status in ^statuses,
          where: post.status == :published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "normalizes string enum values before comparing predicates" do
      query = from(post in Post, where: post.status == "draft", where: post.status == :published)

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "normalizes string enum values inside in predicates" do
      statuses = ["published", "draft", "draft"]

      query =
        from(post in Post,
          where: post.status in ^statuses,
          where: post.status == :archived
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status

      assert issue.meta.predicates == [
               %{operator: :in, values: [:draft, :published]},
               %{operator: :==, values: [:archived]}
             ]
    end

    test "normalizes integer enum dump values before comparing predicates" do
      query =
        from(post in Post,
          where: post.integer_status == 1,
          where: post.integer_status == ^:published
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :integer_status
      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "normalizes integer enum values inside in predicates" do
      statuses = [2, 1, 1]

      query =
        from(post in Post,
          where: post.integer_status in ^statuses,
          where: post.integer_status == :archived
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :integer_status

      assert issue.meta.predicates == [
               %{operator: :in, values: [:draft, :published]},
               %{operator: :==, values: [:archived]}
             ]
    end

    test "ignores invalid enum values because Ecto will reject them separately" do
      query =
        from(post in Post,
          where: post.status == "not-a-status",
          where: post.status == :published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores non enum fields" do
      query = from(post in Post, where: post.title == "draft", where: post.title == "published")

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores schemas without enum fields" do
      query =
        from(post in PlainPost,
          where: post.status == "draft",
          where: post.status == "published"
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum comparisons to another field" do
      query = from(post in Post, where: post.status == post.title, where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum comparisons to joined fields" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: post.status == comment.status,
          where: post.status == :draft
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores greater-than predicates" do
      query = from(post in Post, where: post.status > :draft, where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores negated equality predicates" do
      query = from(post in Post, where: not (post.status == :draft), where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores null checks" do
      query = from(post in Post, where: is_nil(post.status), where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores not equal predicates" do
      query = from(post in Post, where: post.status != :draft, where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores not in predicates" do
      query =
        from(post in Post, where: post.status not in ^[:draft], where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum in predicates on non-root bindings" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: comment.status in [:draft],
          where: post.status == :draft,
          where: post.status == :published
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "ignores enum predicates on non-root bindings" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: comment.status == :draft,
          where: comment.status == :published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum predicates from named non-root bindings" do
      query =
        from(post in Post,
          join: comment in Comment,
          as: :comment,
          on: true,
          where: as(:comment).status == :draft,
          where: as(:comment).status == :published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum in predicates with pinned non-list values" do
      status = :draft
      query = from(post in Post, where: post.status in ^status, where: post.status == :published)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum in predicates with non-literal list values" do
      query = from(post in Post, where: post.status in [post.title], where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum in predicates with joined field values" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: true,
          where: post.status in [comment.status],
          where: post.status == :draft
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum in predicates with non-list expressions" do
      query = from(post in Post, where: post.status in post.title, where: post.status == :draft)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores or_where predicates" do
      query =
        from(post in Post,
          where: post.status == :draft,
          or_where: post.status == :published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores predicates inside or expressions" do
      query = from(post in Post, where: post.status == :draft or post.status == :published)

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum predicates hidden inside fragments" do
      query =
        from(post in Post,
          where: fragment("? = ?", post.status, ^:draft),
          where: post.status == :published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "ignores enum predicates hidden inside exists subqueries" do
      query =
        from(post in Post,
          where:
            exists(
              from(comment in Comment,
                where: comment.status == ^:draft
              )
            ),
          where: post.status == :published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "passes for schema-less sources" do
      query =
        from(post in "posts",
          where: field(post, :status) == ^:draft,
          where: field(post, :status) == ^:published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "passes for named schema-less root bindings" do
      query =
        from(post in "posts",
          as: :post,
          where: field(as(:post), :status) == ^:draft,
          where: field(as(:post), :status) == ^:published
        )

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "returns multiple issues when multiple enum fields conflict" do
      query =
        from(post in Post,
          where: post.status == :draft,
          where: post.status == :published,
          where: post.integer_status == 1,
          where: post.integer_status == 2
        )

      assert {:error, [%Issue{} = first_issue, %Issue{} = second_issue]} =
               ConflictingWherePredicates.validate(:all, query, [])

      assert first_issue.meta.field == :integer_status
      assert second_issue.meta.field == :status
    end

    test "accepts raw enum literal values in supported query AST" do
      query =
        query_with_expr(
          {:and, [],
           [
             {:==, [], [root_field(:status), :draft]},
             {:==, [], [root_field(:status), :published]}
           ]}
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "accepts field expressions in supported query AST" do
      query =
        query_with_expr(
          {:and, [],
           [
             {:==, [], [root_field_call(:status), :draft]},
             {:==, [], [root_field_call(:status), :published]}
           ]}
        )

      assert {:error, %Issue{} = issue} = ConflictingWherePredicates.validate(:all, query, [])

      assert issue.meta.field == :status
      assert Enum.map(issue.meta.predicates, & &1.values) == [[:draft], [:published]]
    end

    test "ignores malformed pinned parameter references" do
      query = query_with_expr({:==, [], [root_field(:status), {:^, [], [1]}]}, [])

      assert :ok = ConflictingWherePredicates.validate(:all, query, [])
    end

    test "respects the explicit query-level escape hatch" do
      query = from(post in Post, where: post.status == :draft, where: post.status == :published)

      assert :ok =
               ConflictingWherePredicates.validate(:all, query,
                 conflicting_where_predicates: [validate: false]
               )
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post, where: post.status == :draft, where: post.status == :published)

      assert {:error, %Issue{} = issue} =
               ConflictingWherePredicates.validate(:all, query,
                 conflicting_where_predicates: [validate: true]
               )

      assert issue.meta.field == :status
    end

    test "requires an explicit false escape hatch" do
      query = from(post in Post, where: post.status == :draft, where: post.status == :published)

      assert {:error, %Issue{}} =
               ConflictingWherePredicates.validate(:all, query,
                 conflicting_where_predicates: [validate: nil]
               )
    end

    test "raises when unsupported options are configured" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown :conflicting_where_predicates option: :fields", fn ->
        ConflictingWherePredicates.validate(:all, query,
          conflicting_where_predicates: [fields: [:status]]
        )
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :conflicting_where_predicates opts to be a keyword list, got: :bad",
                   fn ->
                     ConflictingWherePredicates.validate(:all, query,
                       conflicting_where_predicates: :bad
                     )
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :conflicting_where_predicates opts to be a keyword list, got: [true]",
                   fn ->
                     ConflictingWherePredicates.validate(:all, query,
                       conflicting_where_predicates: [true]
                     )
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: true", fn ->
        ConflictingWherePredicates.validate(:all, query, true)
      end
    end
  end

  defp query_with_expr(expr, params \\ []) do
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
  defp root_field_call(field), do: {:field, [], [{:&, [], [0]}, field]}
end
