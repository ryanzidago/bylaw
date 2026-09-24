defmodule Bylaw.Ecto.Query.ValidateRepoQueryTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query
  alias Bylaw.Ecto.Query.Checks.MandatoryWhereKeys
  alias Bylaw.Ecto.Query.Checks.NamedBindings
  alias Bylaw.Ecto.Query.Checks.RequiredOrder
  alias Bylaw.Ecto.Query.Issue

  defmodule Comment do
    use Ecto.Schema

    schema "comments" do
      field(:post_id, :integer)
      field(:organization_id, :integer)
    end
  end

  @checks [
    RequiredOrder,
    NamedBindings,
    {MandatoryWhereKeys, rules: [fields: [:organization_id]]}
  ]

  test "skips every check for Ecto migrator queries" do
    query = from(migration in "schema_migrations", limit: 1)

    assert :ok = Query.validate_repo_query(:all, query, @checks, schema_migration: true)
  end

  test "validates queries that are neither migrator nor preload queries with every check" do
    query = from(comment in Comment, where: comment.post_id in ^[1])

    assert {:error, issues} = Query.validate_repo_query(:all, query, @checks, [])
    assert Enum.map(issues, & &1.check) == [NamedBindings, NamedBindings, MandatoryWhereKeys]
  end

  test "applies call-site overrides from the :bylaw repo option" do
    query = from(comment in Comment, as: :comment, limit: 1)

    assert {:error, [%Issue{check: RequiredOrder}]} =
             Query.validate_repo_query(:all, query, [RequiredOrder], [])

    assert :ok =
             Query.validate_repo_query(:all, query, [RequiredOrder],
               bylaw: [{RequiredOrder, validate: false}]
             )
  end

  test "disables every check when the :bylaw repo option is false" do
    query = from(comment in Comment, limit: 1)

    assert :ok = Query.validate_repo_query(:all, query, @checks, bylaw: false)
  end

  test "skips checks about how a query was written on Ecto preload queries" do
    query = from(comment in Comment, where: comment.post_id in ^[1])

    assert :ok = Query.validate_repo_query(:all, query, @checks, ecto_query: :preload)
  end

  test "keeps safety checks on Ecto preload queries" do
    query = from(comment in Comment, where: comment.post_id in ^[1], limit: 1)

    assert {:error, [%Issue{check: RequiredOrder}]} =
             Query.validate_repo_query(:all, query, @checks, ecto_query: :preload)
  end

  test "a call-site spec re-enables a skipped check on preload queries" do
    query = from(comment in Comment, where: comment.post_id in ^[1])

    assert {:error, [%Issue{check: NamedBindings} | _issues]} =
             Query.validate_repo_query(:all, query, @checks,
               ecto_query: :preload,
               bylaw: [NamedBindings]
             )
  end
end
