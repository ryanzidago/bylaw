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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id, :user_id]))
    end

    test "passes when any configured key is referenced in keyword where syntax" do
      query = from(post in Post, where: [organisation_id: ^123])

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id, :user_id]))
    end

    test "passes when any configured key is referenced in a dynamic where expression" do
      organisation_id = 123
      predicate = dynamic([post], post.organisation_id == ^organisation_id)
      query = from(post in Post, where: ^predicate)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id, :user_id]))
    end

    test "passes when duplicate configured keys are satisfied" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(
                 :all,
                 query,
                 opts([:organisation_id, :organisation_id])
               )
    end

    test "passes when any configured key is referenced across multiple where clauses" do
      query =
        from(post in Post,
          where: post.title == ^"hello",
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
    end

    test "passes for every Ecto prepare_query operation when the root where predicate is present" do
      query = from(post in Post, where: post.organisation_id == ^123)

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok =
                 MandatoryWhereKeys.validate(operation, query, opts([:organisation_id]))
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when the root where predicate is missing" do
      query = from(post in Post)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, [%Issue{} = issue]} =
                 MandatoryWhereKeys.validate(operation, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(
                 :all,
                 query,
                 opts([:organisation_id, :user_id], match: :all)
               )
    end

    test "returns an issue when no configured key is referenced in a where clause" do
      query = from(post in Post, where: post.title == ^"hello")

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id, :user_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id, :user_id]))
    end

    test "validates only configured keys that exist on the root schema" do
      query = from(post in OrganisationPost, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(
                 :all,
                 query,
                 opts([:organisation_id, :user_id], match: :all)
               )
    end

    test "returns an issue when an applicable root schema key is missing" do
      query = from(post in OrganisationPost, where: post.title == ^"hello")

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id, :user_id]))

      assert issue.meta.keys == [:organisation_id]
      assert issue.meta.missing_keys == [:organisation_id]
      assert issue.meta.found_where_keys == [:title]
    end

    test "continues validating schema-less sources because schema fields cannot be reflected" do
      query = from(post in "posts", where: field(post, :title) == ^"hello")

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.keys == [:organisation_id]
      assert issue.meta.missing_keys == [:organisation_id]
    end

    test "accepts mandatory keys in schema-less source field predicates" do
      query = from(post in "posts", where: field(post, :organisation_id) == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
    end

    test "accepts mandatory keys from a named schema-less root binding" do
      query =
        from(post in "posts",
          as: :post,
          where: field(as(:post), :organisation_id) == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
      assert issue.message == "expected query to filter by at least one of: :organisation_id"
    end

    test "returns an issue when there is no where clause" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
    end

    test "accepts mandatory keys from a named root binding" do
      query =
        from(post in Post,
          as: :post,
          where: as(:post).organisation_id == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
    end

    test "accepts mandatory keys from a named root binding in field predicates" do
      query =
        from(post in Post,
          as: :post,
          where: field(as(:post), :organisation_id) == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(
                 :all,
                 query,
                 opts([:organisation_id, :user_id], match: :all)
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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "accepts mandatory keys in root equality predicates when the field is on the right" do
      query = from(post in Post, where: ^123 == post.organisation_id)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
    end

    test "does not accept mandatory keys in self comparisons" do
      query = from(post in Post, where: post.organisation_id == post.organisation_id)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys compared to another root field" do
      query = from(post in Post, where: post.organisation_id == post.user_id)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "accepts mandatory keys in root in predicates" do
      query = from(post in Post, where: post.organisation_id in ^[123, 456])

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
    end

    test "does not accept mandatory keys in in predicates compared to another root field" do
      query = from(post in Post, where: post.organisation_id in post.allowed_organisation_ids)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
      assert issue.message == "expected query to filter by at least one of: :organisation_id"
    end

    test "does not accept mandatory keys in not in predicates" do
      query = from(post in Post, where: post.organisation_id not in ^[123, 456])

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in not equal predicates" do
      query = from(post in Post, where: post.organisation_id != ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in greater-than predicates" do
      query = from(post in Post, where: post.organisation_id > ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in negated equality predicates" do
      query = from(post in Post, where: not (post.organisation_id == ^123))

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in null checks" do
      query = from(post in Post, where: is_nil(post.organisation_id))

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys hidden inside fragments" do
      query = from(post in Post, where: fragment("? = ?", post.organisation_id, ^123))

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))
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
                 MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id]))

      assert issue.meta.missing_keys == [:organisation_id]

      assert issue.meta.combination_path == [
               %{operation: :union, index: 0},
               %{operation: :union_all, index: 0}
             ]
    end

    test "returns the missing keys when match is all" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(
                 :all,
                 query,
                 opts([:organisation_id, :user_id], match: :all)
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
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id], validate: true))

      assert issue.meta.missing_keys == [:organisation_id]
    end

    test "requires an explicit false validate option" do
      query = from(post in Post)

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query, opts([:organisation_id], validate: nil))
    end

    test "raises when enabled rules are missing" do
      query = from(post in Post)

      assert_raise ArgumentError, "missing required :rules option", fn ->
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

    test "raises when old top-level APIs are used" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown option: :keys", fn ->
        MandatoryWhereKeys.validate(:all, query, keys: [])
      end

      assert_raise ArgumentError, "unknown option: :fields", fn ->
        MandatoryWhereKeys.validate(:all, query, fields: [:organisation_id])
      end

      assert_raise ArgumentError, "unknown option: :match", fn ->
        MandatoryWhereKeys.validate(:all, query, match: :all)
      end
    end

    test "raises when rule fields are empty" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: []",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, rules: [fields: []])
                   end
    end

    test "raises when rule fields are not a list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :fields to be a non-empty list of atoms, got: :organisation_id",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, rules: [fields: :organisation_id])
                   end
    end

    test "raises when rule fields contain non-atoms" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   ~s(expected :fields to contain only atoms, got: "user_id"),
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [fields: [:organisation_id, "user_id"]]
                     )
                   end
    end

    test "raises when rule match is invalid" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected :match to be :any or :all, got: :one", fn ->
        MandatoryWhereKeys.validate(:all, query, rules: [fields: [:organisation_id], match: :one])
      end
    end
  end

  describe "validate/3 with rules" do
    test "accepts the single-rule shorthand" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query, rules: [fields: [:organisation_id]])

      assert issue.meta.missing_keys == [:organisation_id]
    end

    test "scopes rules by plural ecto_schemas matcher" do
      query = from(post in Post)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[where: [ecto_schemas: [Post]], fields: [:organisation_id]]]
               )

      assert issue.meta.missing_keys == [:organisation_id]

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[where: [ecto_schemas: [Organisation]], fields: [:organisation_id]]]
               )
    end

    test "scopes rules by multiple ecto_schemas in one matcher" do
      query = from(post in Post)

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [where: [ecto_schemas: [Organisation, Post]], fields: [:organisation_id]]
                 ]
               )
    end

    test "scopes rules by plural tables matcher with exact and regex values" do
      query = from(post in "posts")

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[where: [tables: ["comments", ~r/^post/]], fields: [:organisation_id]]]
               )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[where: [tables: ["comments", "accounts"]], fields: [:organisation_id]]]
               )
    end

    test "supports OR across a non-empty list of where matcher keyword lists" do
      query = from(post in Post)

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [
                     where: [
                       [tables: ["comments"]],
                       [ecto_schemas: [Post], operations: [:all]]
                     ],
                     fields: [:organisation_id]
                   ]
                 ]
               )
    end

    test "ANDs matcher keys inside one where matcher" do
      query = from(post in Post, prefix: "tenant_a")

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [
                     where: [ecto_schemas: [Post], db_schemas: ["tenant_a"], operations: [:all]],
                     fields: [:organisation_id]
                   ]
                 ]
               )

      assert :ok =
               MandatoryWhereKeys.validate(:delete_all, query,
                 rules: [
                   [
                     where: [ecto_schemas: [Post], db_schemas: ["tenant_a"], operations: [:all]],
                     fields: [:organisation_id]
                   ]
                 ]
               )
    end

    test "scopes rules by plural db_schemas matcher with exact and regex values" do
      query = from(post in Post, prefix: "tenant_a")

      assert {:error, [%Issue{}]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [where: [db_schemas: ["tenant_b", ~r/^tenant_/]], fields: [:organisation_id]]
                 ]
               )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[where: [db_schemas: ["tenant_b"]], fields: [:organisation_id]]]
               )
    end

    @doc """
    Scoped `MandatoryWhereKeys` rules must keep validating the effective root
    source query when the outer prepared query reads from `subquery/1`.

    This matters because `Ecto.Repo.prepare_query/3` only validates the outer
    query. If schema, table, or prefix matchers stop at the wrapper query,
    tenant-boundary rules can silently downgrade from enforcement to `:ok`.
    """
    test "continues enforcing scoped rules through root source subqueries" do
      unscoped_posts =
        from(post in Post,
          prefix: "tenant_a",
          where: post.title == ^"hello"
        )

      scoped_posts =
        from(post in Post,
          prefix: "tenant_a",
          where: post.organisation_id == ^123
        )

      rules = [
        [
          where: [ecto_schemas: [Post], tables: ["posts"], db_schemas: ["tenant_a"]],
          fields: [:organisation_id]
        ]
      ]

      query_missing = from(post in subquery(unscoped_posts), select: count())
      query_present = from(post in subquery(scoped_posts), select: count())

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query_missing, rules: rules)

      assert issue.meta.missing_keys == [:organisation_id]

      assert :ok = MandatoryWhereKeys.validate(:all, query_present, rules: rules)
    end

    test "accepts outer root where predicates on root source subqueries" do
      inner_query = from(post in Post, prefix: "tenant_a")

      query =
        from(post in subquery(inner_query),
          where: post.organisation_id == ^123,
          select: count()
        )

      rules = [
        [
          where: [ecto_schemas: [Post], tables: ["posts"], db_schemas: ["tenant_a"]],
          fields: [:organisation_id]
        ]
      ]

      assert :ok = MandatoryWhereKeys.validate(:all, query, rules: rules)
    end

    test "accepts mandatory keys split across outer and inner root source subqueries" do
      inner_query =
        from(post in Post,
          prefix: "tenant_a",
          where: post.organisation_id == ^123
        )

      query =
        from(post in subquery(inner_query),
          where: post.user_id == ^456,
          select: count()
        )

      rules = [
        [
          where: [ecto_schemas: [Post], tables: ["posts"], db_schemas: ["tenant_a"]],
          fields: [:organisation_id, :user_id],
          match: :all
        ]
      ]

      assert :ok = MandatoryWhereKeys.validate(:all, query, rules: rules)
    end

    test "scopes rules by plural operations matcher" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [[where: [operations: [:delete_all]], fields: [:user_id]]]
               )

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:delete_all, query,
                 rules: [[where: [operations: [:delete_all, :update_all]], fields: [:user_id]]]
               )

      assert issue.meta.missing_keys == [:user_id]
    end

    test "supports except matchers" do
      query = from(post in Post)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [
                     where: [ecto_schemas: [Post]],
                     except: [tables: ["posts"]],
                     fields: [:organisation_id]
                   ]
                 ]
               )
    end

    test "supports except as a non-empty list of matcher keyword lists" do
      query = from(post in Post)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [
                     where: [ecto_schemas: [Post]],
                     except: [[tables: ["comments"]], [operations: [:all]]],
                     fields: [:organisation_id]
                   ]
                 ]
               )
    end

    test "supports complex configurations with multiple accumulating rules" do
      query = from(post in Post, prefix: "tenant_a", where: post.organisation_id == ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [
                     where: [
                       ecto_schemas: [Post, Organisation],
                       operations: [:all, :stream],
                       db_schemas: ["tenant_a", "tenant_b"]
                     ],
                     fields: [:organisation_id]
                   ],
                   [
                     where: [
                       [ecto_schemas: [Organisation], operations: [:all]],
                       [tables: ["posts"], db_schemas: ["tenant_a"]]
                     ],
                     except: [[tables: ["schema_migrations"]], [operations: [:delete_all]]],
                     fields: [:user_id],
                     match: :all
                   ],
                   [
                     where: [tables: ["comments"]],
                     fields: [:allowed_organisation_ids]
                   ]
                 ]
               )

      assert issue.meta.keys == [:user_id]
      assert issue.meta.match == :all
      assert issue.meta.missing_keys == [:user_id]
    end

    test "accumulates all matching rules" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, [%Issue{} = issue]} =
               MandatoryWhereKeys.validate(:all, query,
                 rules: [
                   [where: [ecto_schemas: [Post]], fields: [:organisation_id]],
                   [where: [tables: ["posts"]], fields: [:user_id]]
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
                     where: [ecto_schemas: [Post]],
                     fields: [:organisation_id, :user_id],
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
                   "expected mandatory_where_keys :rules to be a keyword rule or non-empty list of keyword rules",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, rules: [])
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :rules to be a keyword rule or non-empty list of keyword rules",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, rules: :invalid)
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :rules to be a keyword rule or non-empty list of keyword rules",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, rules: [:invalid])
                   end

      assert_raise ArgumentError, "unknown mandatory_where_keys rule option: :unknown", fn ->
        MandatoryWhereKeys.validate(:all, query, rules: [[unknown: true, fields: [:id]]])
      end

      assert_raise ArgumentError, "unknown mandatory_where_keys rule option: :only", fn ->
        MandatoryWhereKeys.validate(:all, query,
          rules: [[only: [tables: ["posts"]], fields: [:id]]]
        )
      end
    end

    test "raises for invalid rule payloads" do
      query = from(post in Post)

      assert_raise ArgumentError, "missing required :fields option", fn ->
        MandatoryWhereKeys.validate(:all, query, rules: [[where: [ecto_schemas: [Post]]]])
      end

      assert_raise ArgumentError, "expected :match to be :any or :all, got: :one", fn ->
        MandatoryWhereKeys.validate(:all, query,
          rules: [[where: [ecto_schemas: [Post]], fields: [:organisation_id], match: :one]]
        )
      end
    end

    test "raises for invalid matcher shapes" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :where to be a matcher or non-empty list of matchers",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[where: [], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "unknown mandatory_where_keys :where matcher option: :ecto_schema",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[where: [ecto_schema: Post], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "unknown mandatory_where_keys :where matcher option: :table",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[where: [table: "posts"], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :where :tables to be a non-empty list of matcher values",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[where: [tables: "posts"], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :where :ecto_schemas to be a non-empty list of matcher values",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[where: [ecto_schemas: Post], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :where :tables to be a non-empty list of matcher values",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[where: [tables: []], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :where :operations to be a non-empty list of matcher values",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[where: [operations: [nil]], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :where :operations to be a non-empty list of matcher values",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[where: [operations: [:invalid]], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :except to be a matcher or non-empty list of matchers",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[except: [], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "unknown mandatory_where_keys :except matcher option: :table",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[except: [table: "posts"], fields: [:organisation_id]]]
                     )
                   end

      assert_raise ArgumentError,
                   "expected mandatory_where_keys :except :tables to be a non-empty list of matcher values",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       rules: [[except: [tables: "posts"], fields: [:organisation_id]]]
                     )
                   end
    end

    test "raises when old top-level payload is mixed with rules" do
      query = from(post in Post)

      assert_raise ArgumentError, "unknown option: :fields", fn ->
        MandatoryWhereKeys.validate(:all, query,
          fields: [:organisation_id],
          rules: [[fields: [:user_id]]]
        )
      end

      assert_raise ArgumentError, "unknown option: :match", fn ->
        MandatoryWhereKeys.validate(:all, query,
          match: :all,
          rules: [[fields: [:organisation_id]]]
        )
      end
    end
  end

  defp opts(fields, extra \\ []) do
    {rule_extra, top_level_extra} = Keyword.split(extra, [:match])
    rule = Keyword.put(rule_extra, :fields, fields)
    Keyword.merge([rules: rule], top_level_extra)
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
