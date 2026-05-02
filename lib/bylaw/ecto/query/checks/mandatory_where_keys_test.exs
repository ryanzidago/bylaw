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
      field(:name, :string)
    end
  end

  describe "validate/3" do
    test "passes when any configured key is referenced in a where clause" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id, :user_id]]
               )
    end

    test "passes when any configured key is referenced in keyword where syntax" do
      query = from(post in Post, where: [organisation_id: ^123])

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id, :user_id]]
               )
    end

    test "passes when any configured key is referenced across multiple where clauses" do
      query =
        from(post in Post,
          where: post.title == ^"hello",
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )
    end

    test "passes for every Ecto prepare_query operation when the root where predicate is present" do
      query = from(post in Post, where: post.organisation_id == ^123)

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok =
                 MandatoryWhereKeys.validate(operation, query,
                   mandatory_where_keys: [keys: [:organisation_id]]
                 )
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when the root where predicate is missing" do
      query = from(post in Post)

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, %Issue{} = issue} =
                 MandatoryWhereKeys.validate(operation, query,
                   mandatory_where_keys: [keys: [:organisation_id]]
                 )

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
                 mandatory_where_keys: [
                   keys: [:organisation_id, :user_id],
                   match: :all
                 ]
               )
    end

    test "returns an issue when no configured key is referenced in a where clause" do
      query = from(post in Post, where: post.title == ^"hello")

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id, :user_id]]
               )

      assert issue.check == MandatoryWhereKeys
      assert issue.code == :missing_mandatory_where_key
      assert issue.meta.keys == [:organisation_id, :user_id]
      assert issue.meta.match == :any
      assert issue.meta.missing_keys == [:organisation_id, :user_id]
      assert issue.meta.found_where_keys == [:title]
    end

    test "passes when the root schema has none of the configured keys" do
      query = from(post in GlobalPost, where: post.title == ^"hello")

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id, :user_id]]
               )
    end

    test "validates only configured keys that exist on the root schema" do
      query = from(post in OrganisationPost, where: post.organisation_id == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [
                   keys: [:organisation_id, :user_id],
                   match: :all
                 ]
               )
    end

    test "returns an issue when an applicable root schema key is missing" do
      query = from(post in OrganisationPost, where: post.title == ^"hello")

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id, :user_id]]
               )

      assert issue.meta.keys == [:organisation_id]
      assert issue.meta.missing_keys == [:organisation_id]
      assert issue.meta.found_where_keys == [:title]
    end

    test "continues validating schema-less sources because schema fields cannot be reflected" do
      query = from(post in "posts", where: field(post, :title) == ^"hello")

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.keys == [:organisation_id]
      assert issue.meta.missing_keys == [:organisation_id]
    end

    test "accepts mandatory keys in schema-less source field predicates" do
      query = from(post in "posts", where: field(post, :organisation_id) == ^123)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )
    end

    test "returns an issue when there is no where clause" do
      query = from(post in Post)

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

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

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

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
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )
    end

    test "does not accept mandatory keys that only appear in an or_where branch" do
      query =
        from(post in Post,
          where: post.title == ^"hello",
          or_where: post.organisation_id == ^123
        )

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys when an or_where branch can match without them" do
      query =
        from(post in Post,
          where: post.organisation_id == ^123,
          or_where: post.title == ^"hello"
        )

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "requires every mandatory key to be present in every or_where branch when match is all" do
      query =
        from(post in Post,
          where: post.organisation_id == ^123,
          or_where: post.user_id == ^456
        )

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [
                   keys: [:organisation_id, :user_id],
                   match: :all
                 ]
               )

      assert issue.meta.missing_keys == [:organisation_id, :user_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys when an or expression branch can match without them" do
      query =
        from(post in Post,
          where: post.organisation_id == ^123 or post.title == ^"hello"
        )

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "accepts mandatory keys in root equality predicates when the field is on the right" do
      query = from(post in Post, where: ^123 == post.organisation_id)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )
    end

    test "does not accept mandatory keys in self comparisons" do
      query = from(post in Post, where: post.organisation_id == post.organisation_id)

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys compared to another root field" do
      query = from(post in Post, where: post.organisation_id == post.user_id)

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

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

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "accepts mandatory keys in root in predicates" do
      query = from(post in Post, where: post.organisation_id in ^[123, 456])

      assert :ok =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )
    end

    test "does not accept mandatory keys in not equal predicates" do
      query = from(post in Post, where: post.organisation_id != ^123)

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in negated equality predicates" do
      query = from(post in Post, where: not (post.organisation_id == ^123))

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys in null checks" do
      query = from(post in Post, where: is_nil(post.organisation_id))

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "does not accept mandatory keys hidden inside fragments" do
      query = from(post in Post, where: fragment("? = ?", post.organisation_id, ^123))

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

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

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert Enum.empty?(issue.meta.found_where_keys)
    end

    test "returns the missing keys when match is all" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, %Issue{} = issue} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [
                   keys: [:organisation_id, :user_id],
                   match: :all
                 ]
               )

      assert issue.meta.missing_keys == [:user_id]
    end

    test "respects the explicit query-level escape hatch" do
      query = from(post in Post)

      assert :ok =
               MandatoryWhereKeys.validate(:all, query, mandatory_where_keys: [validate: false])
    end

    test "requires an explicit false escape hatch" do
      query = from(post in Post)

      assert {:error, %Issue{}} =
               MandatoryWhereKeys.validate(:all, query,
                 mandatory_where_keys: [
                   keys: [:organisation_id],
                   validate: nil
                 ]
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

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :mandatory_where_keys opts to be a keyword list, got: :invalid",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query, mandatory_where_keys: :invalid)
                   end
    end

    test "raises when keys are empty" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected :keys to be a non-empty list of atoms, got: []", fn ->
        MandatoryWhereKeys.validate(:all, query, mandatory_where_keys: [keys: []])
      end
    end

    test "raises when keys are not a list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :keys to be a non-empty list of atoms, got: :organisation_id",
                   fn ->
                     MandatoryWhereKeys.validate(:all, query,
                       mandatory_where_keys: [keys: :organisation_id]
                     )
                   end
    end

    test "raises when keys contain non-atoms" do
      query = from(post in Post)

      assert_raise ArgumentError, ~s(expected :keys to contain only atoms, got: "user_id"), fn ->
        MandatoryWhereKeys.validate(:all, query,
          mandatory_where_keys: [keys: [:organisation_id, "user_id"]]
        )
      end
    end

    test "raises when match is invalid" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected :match to be :any or :all, got: :one", fn ->
        MandatoryWhereKeys.validate(:all, query,
          mandatory_where_keys: [
            keys: [:organisation_id],
            match: :one
          ]
        )
      end
    end
  end
end
