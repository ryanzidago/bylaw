defmodule Bylaw.Ecto.Query.Checks.MandatoryWhereKeysTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.MandatoryWhereKeys
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:organisation_id, :integer)
      field(:allowed_organisation_ids, {:array, :integer})
      field(:user_id, :integer)
      field(:title, :string)
    end
  end

  defmodule OrganisationPost do
    use Ecto.Schema

    schema "organisation_posts" do
      field(:organisation_id, :integer)
      field(:title, :string)
    end
  end

  defmodule GlobalPost do
    use Ecto.Schema

    schema "global_posts" do
      field(:title, :string)
    end
  end

  defmodule Organisation do
    use Ecto.Schema

    schema "organisations" do
      field(:organisation_id, :integer)
      field(:allowed_organisation_ids, {:array, :integer})
      field(:name, :string)
    end
  end

  describe "validate/3" do
    test "passes when any configured key is referenced in a where clause" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id, :user_id])
    end

    test "passes when any configured key is referenced in keyword where syntax" do
      query = from(post in Post, where: [organisation_id: ^123])

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id, :user_id])
    end

    test "passes when any configured key is referenced in a dynamic where expression" do
      organisation_id = 123
      predicate = dynamic([post], post.organisation_id == ^organisation_id)
      query = from(post in Post, where: ^predicate)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id, :user_id])
    end

    test "passes when duplicate configured keys are satisfied" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 keys: [:organisation_id, :organisation_id]
               )
    end

    test "passes when any configured key is referenced across multiple where clauses" do
      query =
        from(post in Post,
          where: post.title == ^"hello",
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "passes for every Ecto prepare_query operation when the root where predicate is present" do
      query = from(post in Post, where: post.organisation_id == ^123)

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok =
                 MandatoryWhereKeys.validate(operation, query, keys: [:organisation_id])
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when the root where predicate is missing" do
      query = from(post in Post)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, [%Issue{} = issue]} =
                 MandatoryWhereKeys.validate(operation, query, keys: [:organisation_id])

        assert issue.meta.operation == operation
        assert issue.meta.missing_keys == [:organisation_id]
      end)
    end

    test "passes when all configured keys are referenced and match is all" do
      query =
        from(post in Post,
          where: post.organisation_id == ^123 and post.user_id == ^456
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 keys: [:organisation_id, :user_id],
                 match: :all
               )
    end

    test "returns an issue when no configured key is referenced in a where clause" do
      query = from(post in Post, where: post.title == ^"hello")

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id, :user_id])

      assert issue.check == MandatoryWhereKeys
      assert issue.meta.keys == [:organisation_id, :user_id]
      assert issue.meta.match == :any
      assert issue.meta.missing_keys == [:organisation_id, :user_id]
      assert issue.meta.found_where_keys == [:title]

      assert issue.message ==
               "expected query to filter by at least one of: :organisation_id, :user_id"
    end

    test "passes when the root schema has none of the configured keys" do
      query = from(post in GlobalPost, where: post.title == ^"hello")

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id, :user_id])
    end

    test "validates only configured keys that exist on the root schema" do
      query = from(post in OrganisationPost, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 keys: [:organisation_id, :user_id],
                 match: :all
               )
    end

    test "returns an issue when an applicable root schema key is missing" do
      query = from(post in OrganisationPost, where: post.title == ^"hello")

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id, :user_id])

      assert issue.meta.keys == [:organisation_id]
      assert issue.meta.missing_keys == [:organisation_id]
      assert issue.meta.found_where_keys == [:title]
    end

    test "continues validating schema-less sources because schema fields cannot be reflected" do
      query = from(post in "posts", where: field(post, :title) == ^"hello")

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.keys == [:organisation_id]
      assert issue.meta.missing_keys == [:organisation_id]
    end

    test "accepts mandatory keys in schema-less source field predicates" do
      query = from(post in "posts", where: field(post, :organisation_id) == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "accepts mandatory keys from a named schema-less root binding" do
      query =
        from(post in "posts",
          as: :post,
          where: field(as(:post), :organisation_id) == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "does not accept mandatory keys from a named schema-less non-root binding" do
      query =
        from(post in "posts",
          as: :post,
          join: comment in "comments",
          as: :comment,
          on: true,
          where: field(as(:comment), :organisation_id) == ^123
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
      assert issue.message == "expected query to filter by at least one of: :organisation_id"
    end

    test "returns an issue when there is no where clause" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys from non-root bindings" do
      query =
        from(post in Post,
          join: organisation in Organisation,
          on: true,
          where: organisation.organisation_id == ^123
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "accepts mandatory keys from the root binding when joins are present" do
      query =
        from(post in Post,
          join: organisation in Organisation,
          on: organisation.organisation_id == post.organisation_id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "accepts mandatory keys from a named root binding" do
      query =
        from(post in Post,
          as: :post,
          where: as(:post).organisation_id == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "accepts mandatory keys from a named root binding in field predicates" do
      query =
        from(post in Post,
          as: :post,
          where: field(as(:post), :organisation_id) == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "does not accept mandatory keys from a named non-root binding" do
      query =
        from(post in Post,
          as: :post,
          join: organisation in Organisation,
          as: :organisation,
          on: true,
          where: as(:organisation).organisation_id == ^123
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
      assert issue.message == "expected query to filter by at least one of: :organisation_id"
    end

    test "does not accept mandatory keys that only appear in an or_where branch" do
      query =
        from(post in Post,
          where: post.title == ^"hello",
          or_where: post.organisation_id == ^123
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys when an or_where branch can match without them" do
      query =
        from(post in Post,
          where: post.organisation_id == ^123,
          or_where: post.title == ^"hello"
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "requires every mandatory key to be present in every or_where branch when match is all" do
      query =
        from(post in Post,
          where: post.organisation_id == ^123,
          or_where: post.user_id == ^456
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 keys: [:organisation_id, :user_id],
                 match: :all
               )

      assert issue.meta.missing_keys == [:organisation_id, :user_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys when an or expression branch can match without them" do
      query =
        from(post in Post,
          where: post.organisation_id == ^123 or post.title == ^"hello"
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "accepts mandatory keys in root equality predicates when the field is on the right" do
      query = from(post in Post, where: ^123 == post.organisation_id)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "does not accept mandatory keys in self comparisons" do
      query = from(post in Post, where: post.organisation_id == post.organisation_id)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys compared to another root field" do
      query = from(post in Post, where: post.organisation_id == post.user_id)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys compared to joined fields" do
      query =
        from(post in Post,
          join: organisation in Organisation,
          on: true,
          where: post.organisation_id == organisation.organisation_id
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "accepts mandatory keys in root in predicates" do
      query = from(post in Post, where: post.organisation_id in ^[123, 456])

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "does not accept mandatory keys in in predicates compared to another root field" do
      query = from(post in Post, where: post.organisation_id in post.allowed_organisation_ids)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
      assert issue.message == "expected query to filter by at least one of: :organisation_id"
    end

    test "does not accept mandatory keys in in predicates compared to joined fields" do
      query =
        from(post in Post,
          join: organisation in Organisation,
          on: true,
          where: post.organisation_id in organisation.allowed_organisation_ids
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
      assert issue.message == "expected query to filter by at least one of: :organisation_id"
    end

    test "does not accept mandatory keys in not in predicates" do
      query = from(post in Post, where: post.organisation_id not in ^[123, 456])

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in not equal predicates" do
      query = from(post in Post, where: post.organisation_id != ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in greater-than predicates" do
      query = from(post in Post, where: post.organisation_id > ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in negated equality predicates" do
      query = from(post in Post, where: not (post.organisation_id == ^123))

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in null checks" do
      query = from(post in Post, where: is_nil(post.organisation_id))

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys hidden inside fragments" do
      query = from(post in Post, where: fragment("? = ?", post.organisation_id, ^123))

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys hidden inside exists subqueries" do
      query =
        from(post in Post,
          where:
            exists(
              from(other_post in Post,
                where: other_post.organisation_id == ^123
              )
            )
        )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "passes when every combination branch references a mandatory key" do
      scoped_posts =
        from(post in Post,
          where: post.organisation_id == ^123,
          select: post.id
        )

      other_scoped_posts =
        from(post in Post,
          where: post.organisation_id == ^456,
          select: post.id
        )

      query = union_all(scoped_posts, ^other_scoped_posts)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])
    end

    test "returns an issue when a combination branch is missing a mandatory key" do
      scoped_posts =
        from(post in Post,
          where: post.organisation_id == ^123,
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
                 MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

        assert issue.meta.missing_keys == [:organisation_id]
        assert issue.meta.found_where_keys == [:title]
        assert issue.meta.combination_path == [%{operation: operation, index: 0}]
      end)
    end

    test "returns every issue when the root and a combination branch are missing mandatory keys" do
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
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      refute Map.has_key?(root_issue.meta, :combination_path)
      assert root_issue.meta.missing_keys == [:organisation_id]

      assert combination_issue.meta.missing_keys == [:organisation_id]
      assert combination_issue.meta.combination_path == [%{operation: :union_all, index: 0}]
    end

    test "tracks nested combination branches missing mandatory keys" do
      scoped_posts =
        from(post in Post,
          where: post.organisation_id == ^123,
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
               MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id])

      assert issue.meta.missing_keys == [:organisation_id]

      assert issue.meta.combination_path == [
               %{operation: :union, index: 0},
               %{operation: :union_all, index: 0}
             ]
    end

    test "returns the missing keys when match is all" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 keys: [:organisation_id, :user_id],
                 match: :all
               )

      assert issue.meta.missing_keys == [:user_id]
      assert issue.message == "expected query to filter by all mandatory keys; missing: :user_id"
    end

    test "respects the explicit validate false option" do
      query = from(post in Post)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, validate: false)
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 keys: [:organisation_id],
                 validate: true
               )

      assert issue.meta.missing_keys == [:organisation_id]
    end

    test "requires an explicit false validate option" do
      query = from(post in Post)

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 keys: [:organisation_id],
                 validate: nil
               )
    end

    test "raises when keys are missing" do
      query = from(post in Post)

      assert_raise ArgumentError, "missing required :keys option", fn ->
        MandatoryWhereKeys.validate(:all, query, [])
      end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        MandatoryWhereKeys.validate(:all, query, :invalid)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:invalid]", fn ->
        MandatoryWhereKeys.validate(:all, query, [:invalid])
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: :invalid",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, :invalid)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [:invalid]",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, [:invalid])
                   end
    end

    test "raises when a check option is unknown" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown option: :unknown", fn ->
        MandatoryWhereKeys.validate(:all, query, unknown: true)
      end
    end

    test "raises when keys are empty" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected :keys to be a non-empty list of atoms, got: []", fn ->
        MandatoryWhereKeys.validate(:all, query, keys: [])
      end
    end

    test "raises when keys are not a list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :keys to be a non-empty list of atoms, got: :organisation_id",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, keys: :organisation_id)
                   end
    end

    test "raises when keys contain non-atoms" do
      query = from(post in Post)

      assert_raise ArgumentError, ~s(expected :keys to contain only atoms, got: "user_id"), fn ->
        MandatoryWhereKeys.validate(:all, query, keys: [:organisation_id, "user_id"])
      end
    end

    test "raises when match is invalid" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected :match to be :any or :all, got: :one", fn ->
        MandatoryWhereKeys.validate(:all, query,
          keys: [:organisation_id],
          match: :one
        )
      end
    end
  end

  describe "validate/3 with rules" do
    test "scopes rules by ecto_schema" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [ecto_schema: Post], keys: [:organisation_id]]]
               )

      assert issue.meta.missing_keys == [:organisation_id]

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [ecto_schema: Organisation], keys: [:organisation_id]]]
               )
    end

    test "scopes rules by ecto_schema lists" do
      query = from(post in Post)

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [ecto_schema: [Organisation, Post]], keys: [:organisation_id]]]
               )
    end

    test "scopes rules by table exact, regex, and list matchers" do
      query = from(post in "posts")

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [table: "posts"], keys: [:organisation_id]]]
               )

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [table: ~r/^post/], keys: [:organisation_id]]]
               )

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [table: ["comments", "posts"]], keys: [:organisation_id]]]
               )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [table: "comments"], keys: [:organisation_id]]]
               )
    end

    test "supports a non-empty list of matcher keyword lists" do
      query = from(post in Post)

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [
                     only: [[table: "comments"], [ecto_schema: Post, operation: :all]],
                     keys: [:organisation_id]
                   ]
                 ]
               )
    end

    test "scopes rules by db_schema exact, regex, and list matchers" do
      query = from(post in Post, prefix: "tenant_a")

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [db_schema: "tenant_a"], keys: [:organisation_id]]]
               )

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [db_schema: ~r/^tenant_/], keys: [:organisation_id]]]
               )

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [only: [db_schema: ["tenant_b", "tenant_a"]], keys: [:organisation_id]]
                 ]
               )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [db_schema: "tenant_b"], keys: [:organisation_id]]]
               )
    end

    test "scopes rules by operation" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[only: [operation: :delete_all], keys: [:user_id]]]
               )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:delete_all, query,
                 rules: [[only: [operation: [:delete_all, :update_all]], keys: [:user_id]]]
               )

      assert issue.meta.missing_keys == [:user_id]
    end

    test "supports except matchers" do
      query = from(post in Post)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [only: [ecto_schema: Post], except: [table: "posts"], keys: [:organisation_id]]
                 ]
               )
    end

    test "supports where as an alias for only" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[where: [ecto_schema: Post], keys: [:organisation_id]]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
    end

    test "accumulates all matching rules" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [only: [ecto_schema: Post], keys: [:organisation_id]],
                   [only: [table: "posts"], keys: [:user_id]]
                 ]
               )

      assert issue.meta.keys == [:user_id]
      assert issue.meta.missing_keys == [:user_id]
    end

    test "uses rule-level match options" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [
                     only: [ecto_schema: Post],
                     keys: [:organisation_id, :user_id],
                     match: :all
                   ]
                 ]
               )

      assert issue.meta.match == :all
      assert issue.meta.missing_keys == [:user_id]
    end

    test "raises for invalid rule shapes" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :rules to be a non-empty list of keyword rules",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, rules: [])
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys rule to include :only or :where, not both",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[only: [table: "posts"], where: [table: "posts"], keys: [:id]]]
                     )
                   end

      assert_raise ArgumentError, "unknown mandatory_where_keys rule option: :unknown", fn ->
        MandatoryWhereKeys.validate(:all, query, rules: [[unknown: true, keys: [:id]]])
      end
    end

    test "raises for invalid matcher shapes" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :only to be a matcher or non-empty list of matchers",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[only: [], keys: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "unknown mandatory_where_keys :only matcher option: :schema",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[only: [schema: Post], keys: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :only :table to be a matcher value or non-empty list of matcher values",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[only: [table: :posts], keys: [:organisation_id]]]
                     )
                   end
    end

    test "raises when old shorthand payload is mixed with rules" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected mandatory_where_keys to use rule-level :keys when :rules is provided",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       keys: [:organisation_id],
                       rules: [[keys: [:user_id]]]
                     )
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
