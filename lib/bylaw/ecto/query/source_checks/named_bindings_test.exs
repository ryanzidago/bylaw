defmodule Bylaw.Ecto.Query.SourceChecks.NamedBindingsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Ecto.Query.Issue
  alias Bylaw.Ecto.Query.SourceChecks.NamedBindings

  describe "validate/2" do
    test "passes when a single-table query declares and references a named root binding" do
      source = """
      from(post in Post,
        as: :post,
        where: as(:post).organisation_id == ^organisation_id
      )
      """

      assert :ok = NamedBindings.validate(source)
    end

    test "requires a named root binding even for a single-table query" do
      source = """
      from(post in Post,
        where: post.organisation_id == ^organisation_id
      )
      """

      assert {:error, issues} = NamedBindings.validate(source)

      assert_reasons(issues, [:missing_root_as, :binding_variable_reference])
      assert Enum.any?(issues, &(Map.get(&1.meta, :variable) == :post))
    end

    test "rejects local binding variables when the root binding has an alias" do
      source = """
      from(post in Post,
        as: :post,
        where: post.organisation_id == ^organisation_id
      )
      """

      assert {:error, [%Issue{} = issue]} = NamedBindings.validate(source)
      assert issue.check == NamedBindings
      assert issue.meta.reason == :binding_variable_reference
      assert issue.meta.variable == :post
      assert issue.message == "expected Ecto query binding reference post to use as(:name)"
    end

    test "rejects keyword field shortcuts because they imply the root binding" do
      source = """
      from(Post,
        as: :post,
        where: [organisation_id: ^organisation_id]
      )
      """

      assert {:error, [%Issue{} = issue]} = NamedBindings.validate(source)
      assert issue.meta.reason == :implicit_binding_reference
      assert issue.meta.macro == :where

      assert issue.message ==
               "expected Ecto query where to use as(:name) references instead of keyword field shortcuts"
    end

    test "rejects atom field shortcuts because they imply the root binding" do
      source = """
      from(Post,
        as: :post,
        select: [:id],
        order_by: [desc: :inserted_at]
      )
      """

      assert {:error, issues} = NamedBindings.validate(source)

      assert_reasons(issues, [
        :implicit_binding_reference,
        :implicit_binding_reference
      ])

      assert Enum.map(issues, & &1.meta.macro) == [:select, :order_by]
    end

    test "passes field expressions that use named binding references" do
      source = """
      from(post in Post,
        as: :post,
        where: field(as(:post), :organisation_id) == ^organisation_id
      )
      """

      assert :ok = NamedBindings.validate(source)
    end

    test "rejects field expressions that use local binding variables" do
      source = """
      from(post in Post,
        as: :post,
        where: field(post, :organisation_id) == ^organisation_id
      )
      """

      assert {:error, [%Issue{} = issue]} = NamedBindings.validate(source)
      assert issue.meta.reason == :binding_variable_reference
      assert issue.meta.variable == :post
      assert issue.meta.reference == :field
    end

    test "requires a named root binding when from omits an in binding" do
      source = "from(Post)"

      assert {:error, [%Issue{} = issue]} = NamedBindings.validate(source)
      assert issue.meta.reason == :missing_root_as
      assert issue.meta.binding == :root
    end

    test "does not count a join alias as the root alias" do
      source = """
      from(post in Post,
        join: comment in Comment,
        as: :comment,
        on: true
      )
      """

      assert {:error, [%Issue{} = issue]} = NamedBindings.validate(source)
      assert issue.meta.reason == :missing_root_as
      assert issue.meta.binding == :root
    end

    test "passes when joins declare aliases and expressions use named references" do
      source = """
      from(post in Post,
        as: :post,
        join: comment in Comment,
        as: :comment,
        on: as(:comment).post_id == as(:post).id,
        where: as(:post).organisation_id == ^organisation_id
      )
      """

      assert :ok = NamedBindings.validate(source)
    end

    test "requires every keyword join to declare an alias" do
      source = """
      from(post in Post,
        as: :post,
        join: comment in Comment,
        on: as(:comment).post_id == as(:post).id
      )
      """

      assert {:error, [%Issue{} = issue]} = NamedBindings.validate(source)
      assert issue.meta.reason == :missing_join_as
      assert issue.meta.join == :join
      assert issue.message == "expected Ecto query join binding to declare an :as alias"
    end

    test "returns issues for every keyword join that omits an alias" do
      source = """
      from(post in Post,
        as: :post,
        join: comment in Comment,
        on: true,
        left_join: tag in Tag,
        on: true
      )
      """

      assert {:error, issues} = NamedBindings.validate(source)

      assert_reasons(issues, [:missing_join_as, :missing_join_as])
      assert Enum.map(issues, & &1.meta.join) == [:join, :left_join]
    end

    test "rejects local binding variables in join sources and predicates" do
      source = """
      from(post in Post,
        as: :post,
        join: comment in assoc(post, :comments),
        as: :comment,
        on: comment.post_id == post.id
      )
      """

      assert {:error, issues} = NamedBindings.validate(source)

      assert_reasons(issues, [
        :binding_variable_reference,
        :binding_variable_reference,
        :binding_variable_reference
      ])

      assert Enum.map(issues, & &1.meta.variable) == [:post, :comment, :post]
    end

    test "passes documented join source forms when aliases are declared" do
      sources = [
        """
        from(post in "posts",
          as: :post,
          join: comment in "comments",
          as: :comment,
          on: field(as(:comment), :post_id) == field(as(:post), :id)
        )
        """,
        """
        from(post in Post,
          as: :post,
          join: comment in assoc(as(:post), :comments),
          as: :comment,
          on: true
        )
        """,
        """
        from(post in Post,
          as: :post,
          join: stats in fragment("select ? as post_id", as(:post).id),
          as: :stats,
          on: field(as(:stats), :post_id) == as(:post).id
        )
        """,
        """
        from(post in Post,
          as: :post,
          join:
            comment in subquery(
              from(comment in Comment,
                as: :comment,
                where: as(:comment).post_id == parent_as(:post).id
              )
            ),
          as: :comment,
          on: true
        )
        """,
        """
        from(post in Post,
          as: :post,
          join: comment in ^comments_query,
          as: :comment,
          on: true
        )
        """
      ]

      Enum.each(sources, fn source ->
        assert :ok = NamedBindings.validate(source)
      end)
    end

    test "rejects pipeline join binding lists and local join references" do
      source = """
      Post
      |> from(as: :post)
      |> join(:inner, [post], comment in assoc(post, :comments),
        as: :comment,
        on: comment.post_id == post.id
      )
      """

      assert {:error, issues} = NamedBindings.validate(source)

      assert_reasons(issues, [
        :binding_list,
        :binding_variable_reference,
        :binding_variable_reference,
        :binding_variable_reference
      ])

      assert Enum.map(Enum.drop(issues, 1), & &1.meta.variable) == [:post, :comment, :post]
    end

    test "rejects dynamic expressions with positional binding lists" do
      source = """
      dynamic([post], post.organisation_id == ^organisation_id)
      """

      assert {:error, issues} = NamedBindings.validate(source)

      assert_reasons(issues, [:binding_list, :binding_variable_reference])
      assert Enum.any?(issues, &(Map.get(&1.meta, :macro) == :dynamic))
      assert Enum.any?(issues, &(Map.get(&1.meta, :variable) == :post))
    end

    test "rejects dynamic expressions with named binding lists" do
      source = """
      dynamic([post: post], as(:post).organisation_id == ^organisation_id)
      """

      assert {:error, [%Issue{} = issue]} = NamedBindings.validate(source)
      assert issue.meta.reason == :binding_list
      assert issue.meta.macro == :dynamic
    end

    test "passes dynamic expressions that use named binding references" do
      source = """
      dynamic(as(:post).organisation_id == ^organisation_id)
      """

      assert :ok = NamedBindings.validate(source)
    end

    test "rejects pipeline query binding lists" do
      source = """
      Post
      |> where([post], post.organisation_id == ^organisation_id)
      """

      assert {:error, issues} = NamedBindings.validate(source)

      assert_reasons(issues, [:binding_list, :binding_variable_reference])
      assert Enum.any?(issues, &(Map.get(&1.meta, :macro) == :where))
      assert Enum.any?(issues, &(Map.get(&1.meta, :variable) == :post))
    end

    test "passes pipeline queries that declare and reference named bindings" do
      source = """
      Post
      |> from(as: :post)
      |> where(as(:post).organisation_id == ^organisation_id)
      """

      assert :ok = NamedBindings.validate(source)
    end

    test "requires pipeline joins to declare aliases" do
      source = """
      Post
      |> from(as: :post)
      |> join(:inner, [], comment in Comment, on: true)
      """

      assert {:error, [%Issue{} = issue]} = NamedBindings.validate(source)
      assert issue.meta.reason == :missing_join_as
    end

    test "accepts parent_as references in subqueries" do
      source = """
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
      """

      assert :ok = NamedBindings.validate(source)
    end

    test "respects the explicit source-level escape hatch" do
      source = "from(post in Post, where: post.organisation_id == ^organisation_id)"

      assert :ok = NamedBindings.validate(source, named_bindings: [validate: false])
    end

    test "validates when validate is explicitly true" do
      source = "from(post in Post, where: post.organisation_id == ^organisation_id)"

      assert {:error, [%Issue{} | _issues]} =
               NamedBindings.validate(source, named_bindings: [validate: true])
    end

    test "requires an explicit false escape hatch" do
      source = "from(post in Post, where: post.organisation_id == ^organisation_id)"

      assert {:error, [%Issue{} | _issues]} =
               NamedBindings.validate(source, named_bindings: [validate: nil])
    end

    test "raises when source is not a string" do
      assert_raise ArgumentError, "expected source to be a string, got: :invalid", fn ->
        NamedBindings.validate(:invalid)
      end
    end

    test "raises when top-level opts are not a keyword list" do
      assert_raise ArgumentError, "expected opts to be a keyword list, got: :invalid", fn ->
        NamedBindings.validate("from(Post)", :invalid)
      end
    end

    test "raises when check opts are not a keyword list" do
      assert_raise ArgumentError,
                   "expected :named_bindings opts to be a keyword list, got: :invalid",
                   fn ->
                     NamedBindings.validate("from(Post)", named_bindings: :invalid)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      assert_raise ArgumentError,
                   "expected :named_bindings opts to be a keyword list, got: [true]",
                   fn ->
                     NamedBindings.validate("from(Post)", named_bindings: [true])
                   end
    end

    test "raises when unsupported options are configured" do
      assert_raise ArgumentError, "unknown :named_bindings option: :bindings", fn ->
        NamedBindings.validate("from(Post)", named_bindings: [bindings: [:post]])
      end
    end
  end

  defp assert_reasons(issues, reasons) do
    assert Enum.map(issues, & &1.meta.reason) == reasons
  end
end
