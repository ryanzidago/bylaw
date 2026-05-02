defmodule Bylaw.Ecto.Query.Checks.NamedBindingsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.NamedBindings
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:organisation_id, :integer)
      field(:title, :string)

      has_many(:comments, Bylaw.Ecto.Query.Checks.NamedBindingsTest.Comment)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:organisation_id, :integer)
      field(:body, :string)

      belongs_to(:post, Bylaw.Ecto.Query.Checks.NamedBindingsTest.Post)
    end
  end

  describe "validate/3" do
    test "passes when root expressions use named binding references" do
      query =
        from(post in Post,
          as: :post,
          where: as(:post).organisation_id == ^123,
          select: as(:post).id
        )

      assert :ok = NamedBindings.validate(:all, query, [])
    end

    test "passes for every Ecto prepare_query operation when named references are used" do
      query =
        from(post in Post,
          as: :post,
          where: as(:post).organisation_id == ^123
        )

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok = NamedBindings.validate(operation, query, [])
      end)
    end

    test "requires a named root binding" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, issues} = NamedBindings.validate(:all, query, [])

      assert_reasons(issues, [:missing_root_as, :positional_binding_reference])
      assert Enum.any?(issues, &(Map.get(&1.meta, :binding) == :root))
    end

    test "does not count a join alias as the root alias" do
      query =
        from(post in Post,
          join: comment in Comment,
          as: :comment,
          on: true
        )

      assert {:error, %Issue{} = issue} = NamedBindings.validate(:all, query, [])
      assert issue.check == NamedBindings
      assert issue.meta.reason == :missing_root_as
      assert issue.meta.binding == :root
    end

    test "requires every join to declare an alias" do
      query =
        from(post in Post,
          as: :post,
          join: comment in Comment,
          on: as(:comment).post_id == as(:post).id
        )

      assert {:error, %Issue{} = issue} = NamedBindings.validate(:all, query, [])
      assert issue.meta.reason == :missing_join_as
      assert issue.meta.join_index == 0
      assert issue.meta.binding_index == 1
      assert issue.message == "expected Ecto query join binding to declare an :as alias"
    end

    test "returns issues for every join that omits an alias" do
      query =
        from(post in Post,
          as: :post,
          join: comment in Comment,
          on: true,
          left_join: second_comment in Comment,
          on: true
        )

      assert {:error, issues} = NamedBindings.validate(:all, query, [])

      assert_reasons(issues, [:missing_join_as, :missing_join_as])
      assert Enum.map(issues, & &1.meta.join_index) == [0, 1]
      assert Enum.map(issues, & &1.meta.binding_index) == [1, 2]
    end

    test "rejects root field references that Ecto expanded from local bindings" do
      query =
        from(post in Post,
          as: :post,
          where: post.organisation_id == ^123
        )

      assert {:error, %Issue{} = issue} = NamedBindings.validate(:all, query, [])
      assert issue.meta.reason == :positional_binding_reference
      assert issue.meta.macro == :where
      assert issue.meta.binding_index == 0
      assert issue.meta.binding_alias == :post
      assert issue.meta.field == :organisation_id
      assert issue.meta.reference == :field_access

      assert issue.message ==
               "expected Ecto query where field reference on binding :post to use as(:name) or parent_as(:name)"
    end

    test "rejects keyword field shortcuts because Ecto expands them to positional root references" do
      query = from(Post, as: :post, where: [organisation_id: ^123])

      assert {:error, %Issue{} = issue} = NamedBindings.validate(:all, query, [])
      assert issue.meta.reason == :positional_binding_reference
      assert issue.meta.macro == :where
      assert issue.meta.binding_alias == :post
      assert issue.meta.field == :organisation_id
    end

    test "rejects field expressions that use positional bindings" do
      field = :organisation_id

      query =
        from(post in Post,
          as: :post,
          where: field(post, ^field) == ^123
        )

      assert {:error, %Issue{} = issue} = NamedBindings.validate(:all, query, [])
      assert issue.meta.reason == :positional_binding_reference
      assert issue.meta.binding_alias == :post
      assert issue.meta.field == :organisation_id
      assert issue.meta.reference == :field_access
    end

    test "passes joins when aliases are declared and predicates use named references" do
      query =
        from(post in Post,
          as: :post,
          join: comment in Comment,
          as: :comment,
          on: as(:comment).post_id == as(:post).id,
          where: as(:post).organisation_id == ^123
        )

      assert :ok = NamedBindings.validate(:all, query, [])
    end

    test "rejects positional binding references in join predicates" do
      query =
        from(post in Post,
          as: :post,
          join: comment in Comment,
          as: :comment,
          on: comment.post_id == post.id
        )

      assert {:error, issues} = NamedBindings.validate(:all, query, [])

      assert_reasons(issues, [
        :positional_binding_reference,
        :positional_binding_reference
      ])

      assert Enum.map(issues, & &1.meta.macro) == [:join_on, :join_on]
      assert Enum.map(issues, & &1.meta.binding_alias) == [:comment, :post]
      assert Enum.map(issues, & &1.meta.field) == [:post_id, :id]
    end

    test "allows association join sources because Ecto stores them as association metadata" do
      query =
        from(post in Post,
          as: :post,
          join: comment in assoc(post, :comments),
          as: :comment,
          on: true
        )

      assert :ok = NamedBindings.validate(:all, query, [])
    end

    test "allows joined preloads because Ecto stores them as association indexes" do
      query =
        from(post in Post,
          as: :post,
          join: comment in assoc(post, :comments),
          as: :comment,
          on: true,
          preload: [comments: comment]
        )

      assert :ok = NamedBindings.validate(:all, query, [])
    end

    test "rejects positional references in ordering, grouping, distinct, windows, and updates" do
      query =
        from(post in Post,
          as: :post,
          order_by: post.title,
          group_by: post.organisation_id,
          distinct: post.id,
          windows: [by_organisation: [partition_by: post.organisation_id]],
          update: [set: [title: post.title]]
        )

      assert {:error, issues} = NamedBindings.validate(:update_all, query, [])

      assert Enum.map(issues, & &1.meta.macro) == [
               :order_by,
               :group_by,
               :distinct,
               :update,
               :windows
             ]

      assert Enum.all?(issues, &(&1.meta.reason == :positional_binding_reference))
      assert Enum.all?(issues, &(&1.meta.binding_alias == :post))
    end

    test "validates nested subqueries" do
      query =
        from(post in Post,
          as: :post,
          where:
            exists(
              from(comment in Comment,
                as: :comment,
                where: comment.post_id == parent_as(:post).id
              )
            )
        )

      assert {:error, %Issue{} = issue} = NamedBindings.validate(:all, query, [])
      assert issue.meta.reason == :positional_binding_reference
      assert issue.meta.binding_alias == :comment
      assert issue.meta.field == :post_id
    end

    test "accepts parent_as references in nested subqueries" do
      query =
        from(post in Post,
          as: :post,
          where:
            exists(
              from(comment in Comment,
                as: :comment,
                where: as(:comment).post_id == parent_as(:post).id
              )
            )
        )

      assert :ok = NamedBindings.validate(:all, query, [])
    end

    test "does not reject whole-binding selects because Ecto has no as(:name) equivalent" do
      query = from(post in Post, as: :post, select: post)

      assert :ok = NamedBindings.validate(:all, query, [])
    end

    test "respects the explicit query-level escape hatch" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert :ok = NamedBindings.validate(:all, query, named_bindings: [validate: false])
    end

    test "validates when validate is explicitly true" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, [%Issue{} | _issues]} =
               NamedBindings.validate(:all, query, named_bindings: [validate: true])
    end

    test "requires an explicit false escape hatch" do
      query = from(post in Post, where: post.organisation_id == ^123)

      assert {:error, [%Issue{} | _issues]} =
               NamedBindings.validate(:all, query, named_bindings: [validate: nil])
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        NamedBindings.validate(:all, query, :invalid)
      end
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post)

      assert_raise ArgumentError,
                   "expected :named_bindings opts to be a keyword list, got: :invalid",
                   fn ->
                     NamedBindings.validate(:all, query, named_bindings: :invalid)
                   end
    end
  end

  defp assert_reasons(issues, reasons) do
    assert Enum.map(List.wrap(issues), & &1.meta.reason) == reasons
  end
end
