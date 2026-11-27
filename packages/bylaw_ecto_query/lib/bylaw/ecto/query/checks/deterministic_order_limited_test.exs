defmodule Bylaw.Ecto.Query.Checks.DeterministicOrderLimitedTest do
  use ExUnit.Case, async: true

  import Ecto.Query
  alias Bylaw.Ecto.Query.Checks.DeterministicOrder
  alias Bylaw.Ecto.Query.Issue

  defmodule Post do
    use Ecto.Schema

    schema "posts" do
      field(:title, :string)
    end
  end

  test "limited scope permits unordered ties when all rows are selected" do
    query = from(p in Post, order_by: p.title)
    assert :ok = DeterministicOrder.validate(:all, query, only: :limited)
    assert {:error, [%Issue{}]} = DeterministicOrder.validate(:all, query, [])
  end

  test "limited scope rejects ambiguous limits and offsets" do
    limited = from(p in Post, order_by: p.title, limit: 10)
    offset = from(p in Post, order_by: p.title, offset: 5)
    assert {:error, [%Issue{}]} = DeterministicOrder.validate(:all, limited, only: :limited)
    assert {:error, [%Issue{}]} = DeterministicOrder.validate(:all, offset, only: :limited)

    assert {:error, [%Issue{}]} =
             DeterministicOrder.validate(:all, first(Post, :title), only: :limited)

    assert {:error, [%Issue{}]} =
             DeterministicOrder.validate(:all, last(Post, :title), only: :limited)
  end

  test "limited scope accepts a unique tie-breaker" do
    query = from(p in Post, order_by: [p.title, p.id], limit: 10)
    assert :ok = DeterministicOrder.validate(:all, query, only: :limited)
  end

  test "limited scope ignores existence shape unless it has an offset" do
    query = from(p in Post, order_by: p.title, select: 1, limit: 1)
    assert :ok = DeterministicOrder.validate(:all, query, only: :limited)

    assert {:error, [%Issue{}]} =
             DeterministicOrder.validate(:all, offset(query, 1), only: :limited)
  end

  test "limited scope rejects invalid scope options" do
    assert_raise ArgumentError, fn ->
      DeterministicOrder.validate(:all, from(p in Post), only: :unknown)
    end
  end
end
