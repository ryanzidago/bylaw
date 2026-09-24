defmodule Bylaw.Ecto.Query.IssueSourceTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query
  alias Bylaw.Ecto.Query.Checks.RequiredOrder
  alias Bylaw.Ecto.Query.Issue

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
    end
  end

  test "issues name the root source of the query" do
    query = from(post in Post, as: :post, limit: 1)

    assert {:error, [%Issue{} = issue]} = Query.validate(:all, query, [RequiredOrder])
    assert issue.meta.source == "posts"
  end

  test "issues name the prefix of a prefixed root source" do
    query = from(post in Post, as: :post, prefix: "tenant", limit: 1)

    assert {:error, [%Issue{} = issue]} = Query.validate(:all, query, [RequiredOrder])
    assert issue.meta.source == "tenant.posts"
  end

  test "a formatted issue names its source" do
    query = from(post in Post, as: :post, limit: 1)

    assert {:error, issues} = Query.validate(:all, query, [RequiredOrder])
    assert Issue.format_many(issues) =~ ~s|(on "posts")|
  end

  test "issues from queries without a known source have no source" do
    assert {:error, [%Issue{} = issue]} =
             Query.validate(:all, %{limit: %{expr: 1}}, [RequiredOrder])

    refute Map.has_key?(issue.meta, :source)
  end
end
