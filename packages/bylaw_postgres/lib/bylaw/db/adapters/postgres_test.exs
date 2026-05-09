defmodule Bylaw.Db.Adapters.PostgresTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  defmodule FailingCheck do
    @behaviour Bylaw.Db.Check

    @impl Bylaw.Db.Check
    def validate(target, _opts) do
      {:error, [%Issue{check: __MODULE__, target: target, message: "failed"}]}
    end
  end

  describe "target/1" do
    test "builds a single Postgres target" do
      query = fn _target, _sql, _params, _opts -> {:ok, %{rows: []}} end

      target =
        Postgres.target(
          query: query,
          dynamic_repo: :tenant_foo,
          meta: %{database: :primary}
        )

      assert target.adapter == Postgres
      assert target.dynamic_repo == :tenant_foo
      assert target.query == query
      assert target.meta == %{database: :primary}
    end

    test "requires keyword options" do
      assert_raise ArgumentError, ~r/expected Postgres target opts to be a keyword list/, fn ->
        Postgres.target([:not_keyword])
      end
    end

    test "requires a repo or query source" do
      assert_raise ArgumentError, ~r/expected Postgres target to include :repo/, fn ->
        Postgres.target([])
      end
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, ~r/unknown Postgres target option: :unknown/, fn ->
        Postgres.target(query: query_fun(), unknown: true)
      end
    end
  end

  describe "validate/2 for target lists" do
    test "delegates check execution for Postgres targets" do
      target = Postgres.target(query: query_fun())

      assert {:error, [%Issue{} = issue]} = Postgres.validate([target], [FailingCheck])
      assert issue.target == target
    end

    test "rejects targets from other adapters" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        Postgres.validate([target], [FailingCheck])
      end
    end

    test "rejects invalid repo or target list input" do
      assert_raise ArgumentError, ~r/expected Postgres repo/, fn ->
        Postgres.validate(nil, [FailingCheck])
      end
    end

    test "rejects manually built targets without a query source" do
      target = %Target{adapter: Postgres}

      assert_raise ArgumentError, ~r/expected Postgres target to include :repo/, fn ->
        Postgres.validate([target], [FailingCheck])
      end
    end

    test "rejects empty target lists" do
      assert_raise ArgumentError, ~r/expected at least one Postgres target/, fn ->
        Postgres.validate([], [FailingCheck])
      end
    end

    test "rejects malformed check lists" do
      target = Postgres.target(query: query_fun())

      assert_raise ArgumentError, ~r/expected checks to be a list/, fn ->
        Postgres.validate([target], FailingCheck)
      end
    end
  end

  describe "validate/2 and validate/3" do
    test "builds one target from repo and checks" do
      assert {:error, [%Issue{} = issue]} =
               Postgres.validate(__MODULE__, [FailingCheck])

      assert issue.check == FailingCheck
      assert issue.target.adapter == Postgres
      assert issue.target.repo == __MODULE__
    end

    test "includes dynamic repo on the target" do
      assert {:error, [%Issue{} = issue]} =
               Postgres.validate(__MODULE__, [FailingCheck], dynamic_repo: :tenant_foo)

      assert issue.target.dynamic_repo == :tenant_foo
    end

    test "rejects unknown validation options" do
      assert_raise ArgumentError, ~r/unknown Postgres validation option: :unknown/, fn ->
        Postgres.validate(__MODULE__, [FailingCheck], unknown: true)
      end
    end

    test "rejects malformed validation options" do
      assert_raise ArgumentError,
                   ~r/expected Postgres validation opts to be a keyword list/,
                   fn ->
                     Postgres.validate(__MODULE__, [FailingCheck], :bad_opts)
                   end
    end

    test "requires a repo module" do
      assert_raise ArgumentError, ~r/expected Postgres repo/, fn ->
        Postgres.validate(nil, [FailingCheck])
      end
    end

    test "rejects malformed check lists" do
      assert_raise ArgumentError, ~r/expected checks to be a list/, fn ->
        Postgres.validate(__MODULE__, FailingCheck)
      end
    end

    test "rejects malformed check specs" do
      assert_raise ArgumentError, ~r/expected check opts to be a keyword list/, fn ->
        Postgres.validate(__MODULE__, [{FailingCheck, :bad_opts}])
      end
    end
  end

  describe "query/4" do
    test "uses an explicit target query callback when present" do
      parent = self()

      target =
        Postgres.target(
          query: fn target, sql, params, opts ->
            send(parent, {:query, target.adapter, sql, params, opts})
            {:ok, %{columns: [], rows: []}}
          end
        )

      assert {:ok, %{rows: []}} = Postgres.query(target, "select 1", [], timeout: 1_000)

      assert_received {:query, Postgres, "select 1", [], [timeout: 1_000]}
    end

    test "returns an error when dynamic repos are requested for unsupported repos" do
      target = Postgres.target(repo: __MODULE__, dynamic_repo: :tenant_foo)

      assert {:error, {:dynamic_repo_not_supported, __MODULE__}} =
               Postgres.query(target, "select 1", [], [])
    end

    test "returns an error when a manually built target has no query source" do
      target = %Target{adapter: Postgres}

      assert {:error, :missing_query_source} = Postgres.query(target, "select 1", [], [])
    end
  end

  defp query_fun do
    fn _target, _sql, _params, _opts -> {:ok, %{columns: [], rows: []}} end
  end
end
