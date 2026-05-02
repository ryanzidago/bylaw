defmodule Bylaw.Db.Adapters.PostgresTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  defmodule FailingCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def name, do: :failing_check

    @impl Bylaw.Db.Check
    def validate(target, _opts) do
      {:error, %Issue{check: __MODULE__, target: target, message: "failed"}}
    end
  end

  describe "target/2" do
    test "builds a single adapter/database/schema target" do
      query = fn _target, _sql, _params, _opts -> {:ok, %{rows: []}} end

      target =
        Postgres.target(:primary_public,
          query: query,
          schema: "public",
          dynamic_repo: :tenant_foo,
          meta: %{database: :primary}
        )

      assert target.adapter == Postgres
      assert target.name == :primary_public
      assert target.schema == "public"
      assert target.dynamic_repo == :tenant_foo
      assert target.query == query
      assert target.meta == %{database: :primary}
    end

    test "requires a schema" do
      assert_raise ArgumentError, ~r/missing required Postgres target option: :schema/, fn ->
        Postgres.target(:primary_public, query: query_fun())
      end
    end

    test "requires keyword options" do
      assert_raise ArgumentError, ~r/expected Postgres target opts to be a keyword list/, fn ->
        Postgres.target(:primary_public, [:not_keyword])
      end
    end

    test "requires a repo or query source" do
      assert_raise ArgumentError, ~r/expected Postgres target to include :repo/, fn ->
        Postgres.target(:primary_public, schema: "public")
      end
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, ~r/unknown Postgres target option: :unknown/, fn ->
        Postgres.target(:primary_public, schema: "public", query: query_fun(), unknown: true)
      end
    end
  end

  describe "validate/2" do
    test "delegates check execution for Postgres targets" do
      target = Postgres.target(:primary_public, schema: "public", query: query_fun())

      assert {:error, %Issue{} = issue} = Postgres.validate(target, [FailingCheck])
      assert issue.target == target
    end

    test "rejects targets from other adapters" do
      target = %Target{adapter: OtherAdapter, name: :other, schema: "public"}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        Postgres.validate(target, [FailingCheck])
      end
    end

    test "rejects missing targets" do
      assert_raise ArgumentError, ~r/expected a Postgres target or list of targets/, fn ->
        Postgres.validate(nil, [FailingCheck])
      end
    end

    test "rejects empty target lists" do
      assert_raise ArgumentError, ~r/expected at least one Postgres target/, fn ->
        Postgres.validate([], [FailingCheck])
      end
    end

    test "rejects malformed check lists" do
      target = Postgres.target(:primary_public, schema: "public", query: query_fun())

      assert_raise ArgumentError, ~r/expected checks to be a list/, fn ->
        Postgres.validate(target, FailingCheck)
      end
    end
  end

  describe "query/4" do
    test "uses an explicit target query callback when present" do
      parent = self()

      target =
        Postgres.target(:primary_public,
          schema: "public",
          query: fn target, sql, params, opts ->
            send(parent, {:query, target.name, sql, params, opts})
            {:ok, %{columns: [], rows: []}}
          end
        )

      assert {:ok, %{rows: []}} = Postgres.query(target, "select 1", [], timeout: 1_000)

      assert_received {:query, :primary_public, "select 1", [], [timeout: 1_000]}
    end

    test "returns an error when a repo target cannot load ecto_sql" do
      target = Postgres.target(:primary_public, repo: __MODULE__, schema: "public")

      assert {:error, {:missing_dependency, :ecto_sql}} =
               Postgres.query(target, "select 1", [], [])
    end
  end

  defp query_fun do
    fn _target, _sql, _params, _opts -> {:ok, %{columns: [], rows: []}} end
  end
end
