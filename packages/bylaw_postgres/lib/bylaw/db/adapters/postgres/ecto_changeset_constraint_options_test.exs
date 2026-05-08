defmodule Bylaw.Db.Adapters.Postgres.EctoChangesetConstraintOptionsTest.Repo do
  @doc false
  @spec config() :: Keyword.t()
  def config, do: [otp_app: :bylaw_postgres]
end

defmodule Bylaw.Db.Adapters.Postgres.EctoChangesetConstraintOptionsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres.EctoChangesetConstraintOptions
  alias Bylaw.Db.Adapters.Postgres.EctoChangesetConstraintOptionsTest.Repo

  @check :ecto_changeset_unique_constraints

  describe "normalize!/3" do
    test "rejects non-list options" do
      assert_raise ArgumentError,
                   "expected #{@check} opts to be a keyword list, got: :invalid",
                   fn ->
                     EctoChangesetConstraintOptions.normalize!(%{}, :invalid, @check)
                   end
    end

    test "rejects non-keyword options" do
      assert_raise ArgumentError,
                   "expected #{@check} opts to be a keyword list, got: [:invalid]",
                   fn ->
                     EctoChangesetConstraintOptions.normalize!(%{}, [:invalid], @check)
                   end
    end

    test "rejects unknown options" do
      assert_raise ArgumentError, "unknown #{@check} option: :unknown", fn ->
        EctoChangesetConstraintOptions.normalize!(%{}, [unknown: true], @check)
      end
    end

    test "validates validate as a boolean" do
      assert_raise ArgumentError,
                   "expected #{@check} :validate to be a boolean, got: :no",
                   fn ->
                     EctoChangesetConstraintOptions.normalize!(%{}, [validate: :no], @check)
                   end
    end

    test "allows disabled validation without schema discovery options" do
      assert [validate: false] =
               EctoChangesetConstraintOptions.normalize!(%{}, [validate: false], @check)
    end

    test "requires schema discovery options when enabled" do
      assert_raise ArgumentError,
                   "expected #{@check} opts to include :otp_app or :schema_modules",
                   fn ->
                     EctoChangesetConstraintOptions.normalize!(%{}, [paths: ["lib"]], @check)
                   end
    end

    test "requires paths when enabled" do
      assert_raise ArgumentError, "expected #{@check} opts to include :paths", fn ->
        EctoChangesetConstraintOptions.normalize!(%{}, [schema_modules: [String]], @check)
      end
    end

    test "validates paths as a non-empty list of strings" do
      assert_raise ArgumentError,
                   "expected #{@check} :paths to be a non-empty list of strings",
                   fn ->
                     EctoChangesetConstraintOptions.normalize!(
                       %{},
                       [schema_modules: [String], paths: []],
                       @check
                     )
                   end
    end

    test "validates schema modules as a non-empty list of modules" do
      assert_raise ArgumentError,
                   "expected #{@check} :schema_modules to be a non-empty list of modules",
                   fn ->
                     EctoChangesetConstraintOptions.normalize!(
                       %{},
                       [schema_modules: [:valid, "invalid"], paths: ["lib"]],
                       @check
                     )
                   end
    end

    test "derives otp_app from the target repo" do
      assert opts =
               EctoChangesetConstraintOptions.normalize!(%{repo: Repo}, [paths: ["lib"]], @check)

      assert opts[:otp_app] == :bylaw_postgres
    end

    test "does not derive otp_app when schema modules are provided" do
      assert opts =
               EctoChangesetConstraintOptions.normalize!(
                 %{repo: Repo},
                 [schema_modules: [String], paths: ["lib"]],
                 @check
               )

      refute Keyword.has_key?(opts, :otp_app)
    end

    test "rejects top-level scope options when rules are provided" do
      assert_raise ArgumentError,
                   "expected #{@check} to use rule-level :schemas when :rules is provided",
                   fn ->
                     EctoChangesetConstraintOptions.normalize!(
                       %{},
                       [
                         schema_modules: [String],
                         paths: ["lib"],
                         rules: [[only: [table: "users"]]],
                         schemas: ["public"]
                       ],
                       @check
                     )
                   end
    end

    test "validates rule matcher keys" do
      assert_raise ArgumentError,
                   "unknown #{@check} :only matcher option: :type",
                   fn ->
                     EctoChangesetConstraintOptions.normalize!(
                       %{},
                       [
                         schema_modules: [String],
                         paths: ["lib"],
                         rules: [[only: [type: "uuid"]]]
                       ],
                       @check
                     )
                   end
    end
  end
end
