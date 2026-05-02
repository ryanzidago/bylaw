defmodule Bylaw.Ecto.Query.IntrospectionTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Introspection

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:organisation_id, :integer)
      field(:status, :string)
      field(:title, :string)
    end
  end

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:organisation_id, :integer)
      field(:post_id, :integer)
    end
  end

  defmodule NotSchema do
  end

  describe "root_schema/1" do
    test "returns the root Ecto schema" do
      query = from(post in Post)

      assert Introspection.root_schema(query) == {:ok, Post}
    end

    test "returns unknown for schema-less and malformed sources" do
      query = from(post in "posts")

      assert Introspection.root_schema(query) == :unknown
      assert Introspection.root_schema(%{from: %{source: {"posts", NotSchema}}}) == :unknown
      assert Introspection.root_schema(:not_a_query) == :unknown
    end
  end

  describe "explicit_join_schema/1" do
    test "returns direct schema joins" do
      query = from(post in Post, join: comment in Comment, on: comment.post_id == post.id)
      [join] = query.joins

      assert Introspection.explicit_join_schema(join) == {:ok, Comment}
    end

    test "skips association, schema-less, and malformed joins" do
      assert Introspection.explicit_join_schema(%{assoc: {:comments, []}}) == :skip
      assert Introspection.explicit_join_schema(%{source: {"comments", nil}}) == :skip
      assert Introspection.explicit_join_schema(%{source: {"comments", NotSchema}}) == :skip
      assert Introspection.explicit_join_schema(:not_a_join) == :skip
    end
  end

  describe "aliases/1 and root_aliases/1" do
    test "return query aliases and named root aliases" do
      query =
        from(post in Post,
          as: :post,
          join: comment in Comment,
          as: :comment,
          on: true
        )

      assert Introspection.aliases(query) == %{post: 0, comment: 1}
      assert Introspection.root_aliases(query) == MapSet.new([:post])
    end

    test "handle missing aliases" do
      assert Introspection.aliases(:not_a_query) == %{}
      assert Introspection.root_aliases(:not_a_query) == MapSet.new()
    end
  end

  describe "query_branches/1 and combination_path_meta/1" do
    test "returns root and nested combination branches" do
      scoped_posts = from(post in Post, where: post.status == "published")
      archived_posts = from(post in Post, where: post.status == "archived")
      nested_query = union_all(scoped_posts, ^archived_posts)
      query = union(scoped_posts, ^nested_query)

      branches = Introspection.query_branches(query)

      assert Enum.map(branches, &elem(&1, 0)) == [
               [],
               [{:union, 0}],
               [{:union, 0}, {:union_all, 0}]
             ]

      assert Enum.all?(branches, fn {_branch_path, branch_query} ->
               Introspection.root_schema(branch_query) == {:ok, Post}
             end)
    end

    test "formats branch paths for issue metadata" do
      assert Introspection.combination_path_meta([]) == %{}

      assert Introspection.combination_path_meta([{:union, 0}, {:union_all, 1}]) == %{
               combination_path: [
                 %{operation: :union, index: 0},
                 %{operation: :union_all, index: 1}
               ]
             }
    end
  end

  describe "binding_index/2" do
    test "returns positional and named binding indexes" do
      aliases = %{post: 0, comment: 1}

      assert Introspection.binding_index({:&, [], [1]}, aliases) == {:ok, 1}
      assert Introspection.binding_index({:as, [], [:comment]}, aliases) == {:ok, 1}
    end

    test "returns unknown for missing or malformed bindings" do
      assert Introspection.binding_index({:as, [], [:missing]}, %{}) == :unknown
      assert Introspection.binding_index({:&, [], [-1]}, %{}) == :unknown
      assert Introspection.binding_index(:not_a_binding, %{}) == :unknown
    end
  end

  describe "field/2" do
    test "returns binding index and field for dot and field call expressions" do
      aliases = %{comment: 1}
      status_field = dot_field({:&, [], [0]}, :status)
      organisation_field = field_call({:as, [], [:comment]}, :organisation_id)

      assert Introspection.field(status_field, aliases) == {:ok, {0, :status}}

      assert Introspection.field(organisation_field, aliases) ==
               {:ok, {1, :organisation_id}}
    end

    test "returns unknown for non-field expressions" do
      assert Introspection.field(:status, %{}) == :unknown
    end
  end

  describe "root_field/2 and root_fields/2" do
    test "accept root positional fields" do
      status_field = dot_field({:&, [], [0]}, :status)
      title_field = field_call({:&, [], [0]}, :title)

      assert Introspection.root_field(status_field, %{}) == {:ok, :status}
      assert Introspection.root_fields(title_field, %{}) == [:title]
    end

    test "accept named root fields from aliases maps" do
      aliases = %{post: 0, comment: 1}
      post_status = dot_field({:as, [], [:post]}, :status)
      comment_status = field_call({:as, [], [:comment]}, :status)

      assert Introspection.root_field(post_status, aliases) == {:ok, :status}

      assert Introspection.root_fields(comment_status, aliases) == []
    end

    test "accept named root fields from root alias sets" do
      root_aliases = MapSet.new([:post])
      post_status = dot_field({:as, [], [:post]}, :status)
      comment_status = field_call({:as, [], [:comment]}, :status)

      assert Introspection.root_field(post_status, root_aliases) == {:ok, :status}

      assert Introspection.root_fields(comment_status, root_aliases) == []
    end
  end

  describe "direct_root_field/2" do
    test "accepts atom and binary root field names" do
      status_field = dot_field({:&, [], [0]}, :status)
      title_field = field_call({:&, [], [0]}, "title")

      assert Introspection.direct_root_field(status_field, %{}) == {:ok, :status}
      assert Introspection.direct_root_field(title_field, %{}) == {:ok, "title"}
    end

    test "unwraps type wrappers around root fields" do
      root_aliases = MapSet.new([:post])
      status_field = type_wrapper(field_call({:as, [], [:post]}, :status), :string)

      assert Introspection.direct_root_field(status_field, root_aliases) == {:ok, :status}
    end

    test "returns unknown for non-root fields and non-field expressions" do
      aliases = %{post: 0, comment: 1}
      comment_status = type_wrapper(field_call({:as, [], [:comment]}, "status"), :string)

      assert Introspection.direct_root_field(comment_status, aliases) == :unknown
      assert Introspection.direct_root_field(:status, aliases) == :unknown
    end
  end

  describe "field_reference?/1" do
    test "detects direct and nested field references" do
      status_field = dot_field({:&, [], [0]}, :status)
      dynamic_status_field = field_call({:&, [], [0]}, "status")
      nested_field = {:in, [], [:status, [field_call({:&, [], [0]}, :id)]]}

      assert Introspection.field_reference?(status_field)
      assert Introspection.field_reference?(dynamic_status_field)
      assert Introspection.field_reference?(nested_field)
    end

    test "returns false when no field references are present" do
      refute Introspection.field_reference?({:in, [], [:status, [:draft, :published]]})
    end
  end

  describe "schema field helpers" do
    test "return schema field metadata" do
      expected_fields = MapSet.new([:id, :status, :title])

      assert MapSet.subset?(expected_fields, Introspection.schema_fields(Post))
      assert Introspection.schema_field?(Post, :status)
      refute Introspection.schema_field?(Post, :missing)
    end
  end

  defp dot_field(source, field), do: {{:., [], [source, field]}, [], []}
  defp field_call(source, field), do: {:field, [], [source, field]}
  defp type_wrapper(expr, type), do: {:type, [], [expr, type]}
end
