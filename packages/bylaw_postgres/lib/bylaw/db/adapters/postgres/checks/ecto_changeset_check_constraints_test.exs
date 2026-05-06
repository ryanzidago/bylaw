defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.CustomSchema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key false
    end
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.MissingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "users" do
    field(:age, :integer)
    field(:name, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    cast(user, attrs, [:age])
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.ProfileOnlyUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "profiles" do
    field(:age, :integer)
    field(:name, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(profile, attrs) do
    cast(profile, attrs, [:name])
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.MatchingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "matching_users" do
    field(:age, :integer)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:age])
    |> check_constraint(:age, name: :matching_users_age_must_be_positive)
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.SuffixMatchingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "suffix_matching_users" do
    field(:age, :integer)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:age])
    |> check_constraint(:age, name: :age_check, match: :suffix)
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraints
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.MatchingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.MissingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.ProfileOnlyUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraintsTest.SuffixMatchingUser
  alias Bylaw.Db.Issue

  describe "validate/2" do
    test "skips validation without discovery options when disabled" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts ->
            flunk("query should not run when validation is disabled")
          end
        )

      assert :ok = EctoChangesetCheckConstraints.validate(target, validate: false)
    end

    test "reports a missing check_constraint for a cast check field" do
      target = target([check("public", "users", "users_age_must_be_positive", ["age"])])

      assert {:error, [%Issue{} = issue]} =
               EctoChangesetCheckConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [MissingUser]
               )

      assert issue.check == EctoChangesetCheckConstraints
      assert issue.message =~ "#{inspect(MissingUser)}.changeset/2"
      assert issue.message =~ ~s/casts :age for table "users"/
      assert issue.message =~ ~s/Postgres has check constraint "users_age_must_be_positive"/
      assert issue.message =~ "does not declare check_constraint(:age)"
      assert issue.meta.constraint_kind == :check
      assert issue.meta.fields == [:age]
    end

    test "does not require a helper when the candidate does not cast the constrained field" do
      target = target([check("public", "profiles", "profiles_age_check", ["age"])])

      assert :ok =
               EctoChangesetCheckConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [ProfileOnlyUser]
               )
    end

    test "passes with an existing explicit check helper" do
      target =
        target([
          check("public", "matching_users", "matching_users_age_must_be_positive", ["age"])
        ])

      assert :ok =
               EctoChangesetCheckConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [MatchingUser]
               )
    end

    test "passes with an existing suffix-matched check helper" do
      target =
        target([
          check("public", "suffix_matching_users", "suffix_matching_users_p0_age_check", [
            "age"
          ])
        ])

      assert :ok =
               EctoChangesetCheckConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [SuffixMatchingUser]
               )
    end
  end

  defp target(rows) do
    Postgres.target(query: fn _target, _sql, _params, _opts -> {:ok, result(rows)} end)
  end

  defp result(rows) do
    %{
      columns: ["schema_name", "table_name", "constraint_name", "column_names"],
      rows: rows
    }
  end

  defp check(schema, table, name, columns), do: [schema, table, name, columns]
end
