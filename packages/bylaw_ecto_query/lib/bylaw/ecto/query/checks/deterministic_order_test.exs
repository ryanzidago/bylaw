defmodule Bylaw.Ecto.Query.Checks.DeterministicOrderTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.DeterministicOrder
  alias Bylaw.Ecto.Query.Issue

  @prepare_query_operations [:all, :update_all, :delete_all, :stream, :insert_all]

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:organisation_id, :integer)
      field(:sequence, :integer)
      field(:slug, :string)
      field(:title, :string)
    end
  end

  defmodule Membership do
    use Ecto.Schema

    @primary_key false
    schema "memberships" do
      field(:organisation_id, :integer, primary_key: true)
      field(:user_id, :integer, primary_key: true)
      field(:name, :string)
    end
  end

  defmodule NoPrimaryKeyPost do
    use Ecto.Schema

    @primary_key false
    schema "no_primary_key_posts" do
      field(:title, :string)
    end
  end

  defmodule CustomSourcePost do
    use Ecto.Schema

    @primary_key {:id, :id, source: :post_id}
    schema "custom_source_posts" do
      field(:slug, :string, source: :post_slug)
      field(:title, :string)
    end
  end

  defmodule Organisation do
    use Ecto.Schema

    schema "organisations" do
      field(:name, :string)
    end
  end

  describe "validate/3" do
    test "passes when there is no order_by clause" do
      query = from(post in Post)

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "passes when bounded queries have no order_by clause" do
      query = from(post in Post, limit: 10)

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "passes when the query is not an Ecto query struct" do
      assert :ok = DeterministicOrder.validate(:stream, :not_a_query, [])
    end

    test "passes when order_by includes the root schema primary key" do
      query = from(post in Post, order_by: [asc: post.title, asc: post.id])

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "passes when the root schema primary key is added in a later order_by clause" do
      query =
        Post
        |> order_by([post], asc: post.title)
        |> order_by([post], asc: post.id)

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "passes when order_by references the root schema primary key with field/2" do
      query = from(post in Post, order_by: [asc: post.title, asc: field(post, :id)])

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "passes when order_by references the primary key with atom field shorthand" do
      query = from(post in Post, order_by: [asc: :title, asc: :id])

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "passes when order_by uses a null-aware direction for the primary key" do
      query = from(post in Post, order_by: [asc: post.title, desc_nulls_last: post.id])

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "passes when Ecto.Query.first/2 and last/2 order by primary key" do
      assert :ok = DeterministicOrder.validate(:all, first(Post), [])
      assert :ok = DeterministicOrder.validate(:all, last(Post), [])
    end

    test "returns an issue when Ecto.Query.first/2 and last/2 use non-primary order fields" do
      assert {:error, [%Issue{} = first_issue]} =
               DeterministicOrder.validate(:all, first(Post, :title), [])

      assert {:error, [%Issue{} = last_issue]} =
               DeterministicOrder.validate(:all, last(Post, :title), [])

      assert first_issue.meta.primary_key == [:id]
      assert first_issue.meta.found_order_keys == [:title]
      assert last_issue.meta.primary_key == [:id]
      assert last_issue.meta.found_order_keys == [:title]
    end

    test "passes for every Ecto prepare_query operation when order_by is deterministic" do
      query = from(post in Post, order_by: [desc: post.title, desc: post.id])

      Enum.each(@prepare_query_operations, fn operation ->
        assert :ok = DeterministicOrder.validate(operation, query, [])
      end)
    end

    test "returns an issue for every Ecto prepare_query operation when order_by is not deterministic" do
      query = from(post in Post, order_by: [asc: post.title])

      Enum.each(@prepare_query_operations, fn operation ->
        assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(operation, query, [])

        assert issue.check == DeterministicOrder
        assert issue.meta.operation == operation
        assert issue.meta.primary_key == [:id]
        assert issue.meta.found_order_keys == [:title]
      end)
    end

    test "does not assume non-primary order fields are unique" do
      query = from(post in Post, order_by: [asc: post.slug])

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:id]
      assert issue.meta.found_order_keys == [:slug]
    end

    test "requires the primary key even when a likely composite unique key is ordered" do
      query = from(post in Post, order_by: [asc: post.organisation_id, asc: post.sequence])

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:id]
      assert issue.meta.found_order_keys == [:organisation_id, :sequence]
    end

    test "accepts a single-column unique key returned by a zero-arity resolver" do
      query = from(post in Post, order_by: [asc: post.slug])

      assert :ok =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn -> %{{nil, "posts"} => [["slug"]]} end
               )
    end

    test "accepts a complete composite unique key returned by the resolver" do
      query = from(post in Post, order_by: [asc: post.organisation_id, asc: post.sequence])

      assert :ok =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn ->
                   %{{nil, "posts"} => [["organisation_id", "sequence"]]}
                 end
               )
    end

    test "rejects an incomplete composite unique key returned by the resolver" do
      query = from(post in Post, order_by: [asc: post.organisation_id])

      assert {:error, [%Issue{} = issue]} =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn ->
                   %{{nil, "posts"} => [["organisation_id", "sequence"]]}
                 end
               )

      assert issue.meta.unique_keys == [["organisation_id", "sequence"]]
      assert issue.meta.found_order_keys == [:organisation_id]
      assert issue.message =~ ~s/("organisation_id", "sequence")/
    end

    test "uses the query database schema to select unique keys" do
      query =
        Post
        |> order_by([post], asc: post.slug)
        |> put_query_prefix("tenant_a")

      assert :ok =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn ->
                   %{
                     {"public", "posts"} => [],
                     {"tenant_a", "posts"} => [["slug"]]
                   }
                 end
               )
    end

    test "accepts unique keys for schema-less table sources" do
      query = from(post in "posts", order_by: [asc: field(post, :slug)])

      assert :ok =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn -> %{{nil, "posts"} => [["slug"]]} end
               )
    end

    test "maps Ecto fields to custom database column sources" do
      query = from(post in CustomSourcePost, order_by: [asc: post.slug])

      assert :ok =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn ->
                   %{{nil, "custom_source_posts"} => [["post_slug"]]}
                 end
               )
    end

    test "lists each verified root unique key once in the issue message" do
      query = from(post in Post, order_by: [asc: post.title])

      assert {:error, [%Issue{} = issue]} =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn ->
                   %{{nil, "posts"} => [["id"], ["slug"]]}
                 end
               )

      assert issue.message ==
               ~s/expected ordered query to include a verified root unique key: ("id") or ("slug")/

      assert issue.meta.primary_key == [:id]
      assert issue.meta.unique_keys == [["id"], ["slug"]]
    end

    test "names verified root unique keys with database columns in the issue message" do
      query = from(post in CustomSourcePost, order_by: [asc: post.title])

      assert {:error, [%Issue{} = issue]} =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn ->
                   %{{nil, "custom_source_posts"} => [["post_id"], ["post_slug"]]}
                 end
               )

      assert issue.message ==
               ~s/expected ordered query to include a verified root unique key: ("post_id") or ("post_slug")/

      refute issue.message =~ ~s/("id")/
      assert issue.meta.primary_key == [:id]
      assert issue.meta.unique_keys == [["post_id"], ["post_slug"]]
    end

    test "offers the reflected primary key when it is absent from the unique key catalogue" do
      query = from(post in Post, order_by: [asc: post.title])

      assert {:error, [%Issue{} = issue]} =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn ->
                   %{{nil, "posts"} => [["slug"]]}
                 end
               )

      assert issue.message ==
               ~s/expected ordered query to include a verified root unique key: ("id") or ("slug")/

      assert issue.meta.primary_key == [:id]
      assert issue.meta.unique_keys == [["slug"]]
    end

    test "keeps issue metadata in its Ecto field and database column domains" do
      query = from(post in CustomSourcePost, order_by: [asc: post.title])

      assert {:error, [%Issue{} = issue]} =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn ->
                   %{{nil, "custom_source_posts"} => [["post_id"], ["post_slug"]]}
                 end
               )

      assert String.starts_with?(
               issue.message,
               "expected ordered query to include a verified root unique key:"
             )

      assert issue.meta.primary_key == [:id]
      assert issue.meta.unique_keys == [["post_id"], ["post_slug"]]
    end

    test "keeps primary-key-only wording when the catalogue has no source entry" do
      query = from(post in Post, order_by: [asc: post.title])

      assert {:error, [%Issue{} = issue]} =
               DeterministicOrder.validate(:all, query, unique_keys: fn -> %{} end)

      assert issue.message == "expected ordered query to include the root primary key: :id"
      assert issue.meta.primary_key == [:id]
      assert Enum.empty?(issue.meta.unique_keys)
    end

    test "invokes the resolver only after primary key reflection cannot prove the order" do
      query = from(post in Post, order_by: [asc: post.id])

      assert :ok =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn -> flunk("resolver should not run") end
               )
    end

    test "does not invoke the resolver for unordered queries" do
      query = from(post in Post)

      assert :ok =
               DeterministicOrder.validate(:all, query,
                 unique_keys: fn -> flunk("resolver should not run") end
               )
    end

    test "does not suppress resolver failures" do
      query = from(post in Post, order_by: [asc: post.slug])

      assert_raise RuntimeError, "catalogue unavailable", fn ->
        DeterministicOrder.validate(:all, query,
          unique_keys: fn -> raise "catalogue unavailable" end
        )
      end
    end

    test "requires every field in a composite primary key" do
      query = from(membership in Membership, order_by: [asc: membership.organisation_id])

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:organisation_id, :user_id]
      assert issue.meta.found_order_keys == [:organisation_id]
    end

    test "passes when order_by includes every field in a composite primary key" do
      query =
        from(membership in Membership,
          order_by: [
            asc: membership.name,
            asc: membership.organisation_id,
            asc: membership.user_id
          ]
        )

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "passes when composite primary key fields are split across order_by clauses" do
      query =
        Membership
        |> order_by([membership], asc: membership.organisation_id)
        |> order_by([membership], asc: membership.user_id)

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "does not accept primary keys hidden inside fragments" do
      query = from(post in Post, order_by: fragment("? + 0", post.id))

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:id]
      assert Enum.empty?(issue.meta.found_order_keys)
    end

    test "returns an issue for schema-less sources because no primary key can be reflected" do
      query = from(post in "posts", order_by: [asc: field(post, :title)])

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert Enum.empty?(issue.meta.primary_key)
      assert issue.meta.found_order_keys == [:title]

      assert issue.message ==
               "expected ordered query to include the root primary key, but no root primary key is known"
    end

    test "returns an issue when a root schema has no primary key" do
      query = from(post in NoPrimaryKeyPost, order_by: [asc: post.title])

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert Enum.empty?(issue.meta.primary_key)
      assert issue.meta.found_order_keys == [:title]
    end

    test "does not accept primary keys from non-root bindings" do
      query =
        from(post in Post,
          join: organisation in Organisation,
          on: true,
          order_by: [asc: organisation.id]
        )

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:id]
      assert Enum.empty?(issue.meta.found_order_keys)
    end

    test "does not accept primary keys referenced with field/2 from non-root bindings" do
      query =
        from(post in Post,
          join: organisation in Organisation,
          on: true,
          order_by: [asc: field(organisation, :id)]
        )

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:id]
      assert Enum.empty?(issue.meta.found_order_keys)
    end

    test "accepts primary keys from named root bindings" do
      query = from(post in Post, as: :post, order_by: [asc: as(:post).id])

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "accepts primary keys referenced with field/2 from named root bindings" do
      query = from(post in Post, as: :post, order_by: [asc: field(as(:post), :id)])

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "does not accept primary keys from named non-root bindings" do
      query =
        from(post in Post,
          as: :post,
          join: organisation in Organisation,
          as: :organisation,
          on: true,
          order_by: [asc: as(:organisation).id]
        )

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:id]
      assert Enum.empty?(issue.meta.found_order_keys)
    end

    test "accepts primary keys from the root binding when joins are present" do
      query =
        from(post in Post,
          join: organisation in Organisation,
          on: organisation.id == post.organisation_id,
          order_by: [asc: organisation.name, asc: post.id]
        )

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "accepts primary keys from raw order expressions without direction tuples" do
      query = raw_order_query([root_field(:id)])

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "accepts primary keys from raw field expressions" do
      query = raw_order_query([root_field_call(:id)])

      assert :ok = DeterministicOrder.validate(:all, query, [])
    end

    test "does not accept raw field expressions from non-root bindings" do
      query = raw_order_query(asc: non_root_field_call(:id))

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:id]
      assert Enum.empty?(issue.meta.found_order_keys)
    end

    test "ignores malformed raw order expressions" do
      query = raw_order_query(:invalid)

      assert {:error, [%Issue{} = issue]} = DeterministicOrder.validate(:all, query, [])

      assert issue.meta.primary_key == [:id]
      assert Enum.empty?(issue.meta.found_order_keys)
    end

    test "respects the explicit validate false option" do
      query = from(post in Post, order_by: [asc: post.title])

      assert :ok =
               DeterministicOrder.validate(:all, query, validate: false)
    end

    test "requires an explicit false validate option" do
      query = from(post in Post, order_by: [asc: post.title])

      assert {:error, [%Issue{}]} =
               DeterministicOrder.validate(:all, query, validate: nil)
    end

    test "raises when the unique keys resolver is not a zero-arity function" do
      query = from(post in Post, order_by: [asc: post.title])

      assert_raise ArgumentError,
                   "expected :unique_keys to be a zero-arity function, got: [[:external_id], :slug]",
                   fn ->
                     DeterministicOrder.validate(:all, query,
                       unique_keys: [[:external_id], :slug]
                     )
                   end
    end

    test "raises when the unique keys resolver does not return a map" do
      query = from(post in Post, order_by: [asc: post.title])

      assert_raise ArgumentError,
                   "expected :unique_keys resolver to return a map, got: []",
                   fn ->
                     DeterministicOrder.validate(:all, query, unique_keys: fn -> [] end)
                   end
    end

    test "raises for malformed unique key catalogue source keys" do
      query = from(post in Post, order_by: [asc: post.title])

      assert_raise ArgumentError,
                   ~r/expected :unique_keys map keys to be/,
                   fn ->
                     DeterministicOrder.validate(:all, query,
                       unique_keys: fn -> %{"posts" => [["id"]]} end
                     )
                   end
    end

    test "raises for malformed unique key catalogue values" do
      query = from(post in Post, order_by: [asc: post.title])

      assert_raise ArgumentError,
                   ~r/expected unique keys for \{nil, "posts"\} to contain/,
                   fn ->
                     DeterministicOrder.validate(:all, query,
                       unique_keys: fn -> %{{nil, "posts"} => [[]]} end
                     )
                   end
    end

    test "accepts unique keys with scoped rules" do
      query = from(post in Post, order_by: [asc: post.slug])

      assert :ok =
               DeterministicOrder.validate(:all, query,
                 rules: [where: [tables: ["posts"]]],
                 unique_keys: fn -> %{{nil, "posts"} => [["slug"]]} end
               )
    end

    test "raises when check opts are not a keyword list" do
      query = from(post in Post, order_by: [asc: post.title])

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: :bad",
                   fn ->
                     DeterministicOrder.validate(:all, query, :bad)
                   end
    end

    test "raises when check opts are a non-keyword list" do
      query = from(post in Post, order_by: [asc: post.title])

      assert_raise ArgumentError,
                   "expected opts to be a keyword list, got: [:bad]",
                   fn ->
                     DeterministicOrder.validate(:all, query, [:bad])
                   end
    end

    test "raises when top-level opts are not a keyword list" do
      query = from(post in Post, order_by: [asc: post.title])

      assert_raise ArgumentError, "expected opts to be a keyword list, got: :bad", fn ->
        DeterministicOrder.validate(:all, query, :bad)
      end
    end

    test "raises when top-level opts are a non-keyword list" do
      query = from(post in Post, order_by: [asc: post.title])

      assert_raise ArgumentError, "expected opts to be a keyword list, got: [:bad]", fn ->
        DeterministicOrder.validate(:all, query, [:bad])
      end
    end
  end

  defp raw_order_query(expr) do
    %{
      aliases: %{},
      from: %{source: {"posts", Post}},
      order_bys: [%{expr: expr}]
    }
  end

  defp root_field(field), do: {{:., [], [{:&, [], [0]}, field]}, [], []}
  defp root_field_call(field), do: {:field, [], [{:&, [], [0]}, field]}
  defp non_root_field_call(field), do: {:field, [], [{:&, [], [1]}, field]}
end
