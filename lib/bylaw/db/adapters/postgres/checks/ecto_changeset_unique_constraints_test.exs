defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.CustomSchema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key false
    end
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.MissingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "users" do
    field(:email, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    cast(user, attrs, [:email])
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.ProfileOnlyUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "profiles" do
    field(:email, :string)
    field(:name, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(profile, attrs) do
    cast(profile, attrs, [:name])
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.MatchingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "matching_users" do
    field(:email, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> unique_constraint(:email)
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.Repo do
  @doc false
  @spec config() :: keyword()
  def config, do: [otp_app: :bylaw]
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraints
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.MatchingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.MissingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.ProfileOnlyUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.Repo
  alias Bylaw.Db.Issue

  describe "validate/2" do
    test "reports a missing unique_constraint for a cast unique field" do
      target = target([unique("public", "users", "users_email_index", ["email"])])

      assert {:error, [%Issue{} = issue]} =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [MissingUser]
               )

      assert issue.check == EctoChangesetUniqueConstraints
      assert issue.message =~ "#{inspect(MissingUser)}.changeset/2"
      assert issue.message =~ ~s/casts :email for table "users"/
      assert issue.message =~ ~s/Postgres has unique index "users_email_index"/
      assert issue.message =~ "does not declare unique_constraint(:email)"
      assert issue.meta.constraint_kind == :unique
      assert issue.meta.fields == [:email]
    end

    test "does not require a helper when the candidate does not cast the constrained field" do
      target = target([unique("public", "profiles", "profiles_email_index", ["email"])])

      assert :ok =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [ProfileOnlyUser]
               )
    end

    test "passes with an existing inferred unique helper" do
      target =
        target([unique("public", "matching_users", "matching_users_email_index", ["email"])])

      assert :ok =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [MatchingUser]
               )
    end
  end

  describe "validate/1" do
    test "derives otp_app from the repo when schema modules are not passed" do
      parent = self()

      assert :ok =
               EctoChangesetUniqueConstraints.validate(
                 repo: Repo,
                 query: fn _target, _sql, _params, _opts ->
                   send(parent, :queried)
                   {:ok, result([])}
                 end,
                 paths: [__ENV__.file]
               )

      assert_received :queried
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

  defp unique(schema, table, name, columns), do: [schema, table, name, columns]
end
