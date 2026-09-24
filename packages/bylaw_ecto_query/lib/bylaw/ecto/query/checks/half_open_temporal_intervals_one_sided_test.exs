defmodule Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervalsOneSidedTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals
  alias Bylaw.Ecto.Query.Issue

  defmodule Token do
    use Ecto.Schema

    schema "tokens" do
      field(:inserted_at, :utc_datetime)
      field(:expires_at, :utc_datetime)
    end
  end

  test "passes a lone exclusive lower bound, such as a validity window" do
    query = from(token in Token, where: token.inserted_at > ago(7, "day"))

    assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
  end

  test "passes a lone exclusive lower bound compared to now" do
    now = DateTime.utc_now()
    query = from(token in Token, where: token.expires_at > ^now)

    assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
  end

  test "passes a lone inclusive upper bound" do
    now = DateTime.utc_now()
    query = from(token in Token, where: token.expires_at <= ^now)

    assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
  end

  test "passes one-sided bounds on different fields" do
    now = DateTime.utc_now()

    query =
      from(token in Token,
        where: token.inserted_at > ago(7, "day"),
        where: token.expires_at <= ^now
      )

    assert :ok = HalfOpenTemporalIntervals.validate(:all, query, [])
  end

  test "returns an issue when a field bounded on both sides has an exclusive lower bound" do
    now = DateTime.utc_now()

    query =
      from(token in Token,
        where: token.inserted_at > ago(7, "day"),
        where: token.inserted_at < ^now
      )

    assert {:error, [%Issue{} = issue]} = HalfOpenTemporalIntervals.validate(:all, query, [])

    assert issue.meta.violations == [
             %{boundary: :lower, operator: :>, expected_operator: :>=}
           ]
  end
end
