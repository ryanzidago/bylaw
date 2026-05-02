defmodule Bylaw.Ecto.Query.Checks.MandatoryJoinKeysTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.MandatoryJoinKeys
  alias Bylaw.Ecto.Query.Issue

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:organisation_id, :integer)
      field(:user_id, :integer)
      field(:title, :string)

      has_many(:comments, Bylaw.Ecto.Query.Checks.MandatoryJoinKeysTest.Comment)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:organisation_id, :integer)
      field(:user_id, :integer)
      field(:body, :string)

      belongs_to(:post, Bylaw.Ecto.Query.Checks.MandatoryJoinKeysTest.Post)
    end
  end

  defmodule Reaction do
    use Ecto.Schema

    schema "reactions" do
      field(:organisation_id, :integer)
      field(:post_id, :integer)
      field(:emoji, :string)
    end
  end

  defmodule GlobalComment do
    use Ecto.Schema

    schema "global_comments" do
      field(:post_id, :integer)
      field(:body, :string)
    end
  end

  describe "validate/3" do
    test "returns an issue when an explicit schema join omits the mandatory key equality" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          where: post.organisation_id == ^123
        )

      assert {:error, %Issue{} = issue} =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )

      assert issue.check == MandatoryJoinKeys
      assert issue.code == :missing_mandatory_join_key
      assert issue.meta.operation == :all
      assert issue.meta.join_index == 0
      assert issue.meta.binding_index == 1
      assert issue.meta.join_schema == Comment
      assert issue.meta.keys == [:organisation_id]
      assert issue.meta.missing_keys == [:organisation_id]
      assert issue.meta.found_join_keys == []
    end

    test "passes when an explicit schema join matches the mandatory key to an earlier binding" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.organisation_id == post.organisation_id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )
    end

    test "passes when the mandatory key equality is written with the joined binding on the right" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and post.organisation_id == comment.organisation_id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )
    end

    test "validates only configured keys that exist on the joined schema" do
      query =
        from(post in Post,
          join: reaction in Reaction,
          on: reaction.post_id == post.id and reaction.organisation_id == post.organisation_id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [
                   keys: [:organisation_id, :user_id],
                   match: :all
                 ]
               )
    end

    test "returns missing keys when match is all" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.organisation_id == post.organisation_id,
          where: post.organisation_id == ^123
        )

      assert {:error, %Issue{} = issue} =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [
                   keys: [:organisation_id, :user_id],
                   match: :all
                 ]
               )

      assert issue.meta.keys == [:organisation_id, :user_id]
      assert issue.meta.found_join_keys == [:organisation_id]
      assert issue.meta.missing_keys == [:user_id]
    end

    test "passes when any configured key is matched and match is any" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.user_id == post.user_id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [
                   keys: [:organisation_id, :user_id],
                   match: :any
                 ]
               )
    end

    test "uses the actual binding index when later joins are missing mandatory key equality" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.organisation_id == post.organisation_id,
          join: reaction in Reaction,
          on: reaction.post_id == post.id,
          where: post.organisation_id == ^123
        )

      assert {:error, %Issue{} = issue} =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.join_index == 1
      assert issue.meta.binding_index == 2
      assert issue.meta.join_schema == Reaction
      assert issue.meta.missing_keys == [:organisation_id]
    end

    test "accepts mandatory key matches to prior non-root bindings" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.organisation_id == post.organisation_id,
          join: reaction in Reaction,
          on: reaction.post_id == post.id and reaction.organisation_id == comment.organisation_id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )
    end

    test "returns multiple issues when multiple explicit joins are missing mandatory key equality" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id,
          join: reaction in Reaction,
          on: reaction.post_id == post.id,
          where: post.organisation_id == ^123
        )

      assert {:error, [%Issue{} = first_issue, %Issue{} = second_issue]} =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )

      assert first_issue.meta.join_index == 0
      assert first_issue.meta.binding_index == 1
      assert first_issue.meta.join_schema == Comment

      assert second_issue.meta.join_index == 1
      assert second_issue.meta.binding_index == 2
      assert second_issue.meta.join_schema == Reaction
    end

    test "passes when the joined schema has none of the configured keys" do
      query =
        from(post in Post,
          join: comment in GlobalComment,
          on: comment.post_id == post.id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )
    end

    test "does not validate schema-less joins" do
      query =
        from(post in Post,
          join: comment in "comments",
          on: field(comment, :post_id) == post.id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )
    end

    test "does not validate subquery joins" do
      comments_query =
        from(comment in Comment,
          where: comment.body == ^"hello"
        )

      query =
        from(post in Post,
          join: comment in subquery(comments_query),
          on: comment.post_id == post.id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )
    end

    test "does not validate fragment joins" do
      query =
        from(post in Post,
          join: comment in fragment("select * from comments"),
          on: comment.post_id == post.id,
          where: post.organisation_id == ^123
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )
    end

    test "does not validate association joins" do
      query =
        from(post in Post,
          join: comment in assoc(post, :comments),
          where: post.organisation_id == ^123,
          select: comment.id
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )
    end

    test "does not accept not equal predicates as mandatory key matches" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.organisation_id != post.organisation_id,
          where: post.organisation_id == ^123
        )

      assert {:error, %Issue{} = issue} =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert issue.meta.found_join_keys == []
    end

    test "does not accept joined keys compared only to query parameters" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id and comment.organisation_id == ^123,
          where: post.organisation_id == ^123
        )

      assert {:error, %Issue{} = issue} =
               MandatoryJoinKeys.validate(:all, query,
                 mandatory_join_keys: [keys: [:organisation_id]]
               )

      assert issue.meta.missing_keys == [:organisation_id]
      assert issue.meta.found_join_keys == []
    end

    test "respects the explicit query-level escape hatch" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert :ok =
               MandatoryJoinKeys.validate(:all, query, mandatory_join_keys: [validate: false])
    end

    test "raises when keys are missing" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert_raise ArgumentError, "missing required :keys option", fn ->
        MandatoryJoinKeys.validate(:all, query, [])
      end
    end

    test "raises when keys are empty" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert_raise ArgumentError, "expected :keys to be a non-empty list of atoms, got: []", fn ->
        MandatoryJoinKeys.validate(:all, query, mandatory_join_keys: [keys: []])
      end
    end

    test "raises when keys contain non-atoms" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert_raise ArgumentError,
                   "expected :keys to contain only atoms, got: \"organisation_id\"",
                   fn ->
                     MandatoryJoinKeys.validate(:all, query,
                       mandatory_join_keys: [keys: ["organisation_id"]]
                     )
                   end
    end

    test "raises when match is invalid" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert_raise ArgumentError, "expected :match to be :any or :all, got: :one", fn ->
        MandatoryJoinKeys.validate(:all, query,
          mandatory_join_keys: [
            keys: [:organisation_id],
            match: :one
          ]
        )
      end
    end

    test "raises when check opts are not a keyword list" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert_raise ArgumentError,
                   "expected :mandatory_join_keys opts to be a keyword list, got: true",
                   fn ->
                     MandatoryJoinKeys.validate(:all, query, mandatory_join_keys: true)
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query =
        from(post in Post,
          join: comment in Comment,
          on: comment.post_id == post.id
        )

      assert_raise ArgumentError, "expected opts to be a keyword list, got: true", fn ->
        MandatoryJoinKeys.validate(:all, query, true)
      end
    end
  end
end
