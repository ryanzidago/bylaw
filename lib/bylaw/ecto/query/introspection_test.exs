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
      assert Introspection.root_schema(from(post in "posts")) == :unknown
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

      assert Introspection.field(dot_field({:&, [], [0]}, :status), aliases) ==
               {:ok, {0, :status}}

      assert Introspection.field(field_call({:as, [], [:comment]}, :organisation_id), aliases) ==
               {:ok, {1, :organisation_id}}
    end

    test "returns unknown for non-field expressions" do
      assert Introspection.field(:status, %{}) == :unknown
    end
  end

  describe "root_field/2 and root_fields/2" do
    test "accept root positional fields" do
      assert Introspection.root_field(dot_field({:&, [], [0]}, :status), %{}) == {:ok, :status}
      assert Introspection.root_fields(field_call({:&, [], [0]}, :title), %{}) == [:title]
    end

    test "accept named root fields from aliases maps" do
      aliases = %{post: 0, comment: 1}

      assert Introspection.root_field(dot_field({:as, [], [:post]}, :status), aliases) ==
               {:ok, :status}

      assert Introspection.root_fields(field_call({:as, [], [:comment]}, :status), aliases) == []
    end

    test "accept named root fields from root alias sets" do
      root_aliases = MapSet.new([:post])

      assert Introspection.root_field(dot_field({:as, [], [:post]}, :status), root_aliases) ==
               {:ok, :status}

      assert Introspection.root_fields(field_call({:as, [], [:comment]}, :status), root_aliases) ==
               []
    end
  end

  describe "field_reference?/1" do
    test "detects direct and nested field references" do
      assert Introspection.field_reference?(dot_field({:&, [], [0]}, :status))

      assert Introspection.field_reference?(
               {:in, [], [:status, [field_call({:&, [], [0]}, :id)]]}
             )
    end

    test "returns false when no field references are present" do
      refute Introspection.field_reference?({:in, [], [:status, [:draft, :published]]})
    end
  end

  describe "schema field helpers" do
    test "return schema field metadata" do
      assert MapSet.subset?(MapSet.new([:id, :status, :title]), Introspection.schema_fields(Post))
      assert Introspection.schema_field?(Post, :status)
      refute Introspection.schema_field?(Post, :missing)
    end
  end

  defp dot_field(source, field), do: {{:., [], [source, field]}, [], []}
  defp field_call(source, field), do: {:field, [], [source, field]}
end
