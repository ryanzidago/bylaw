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

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.PrefixedMissingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.CustomSchema

  import Ecto.Changeset

  @schema_prefix "tenant_a"
  schema "prefixed_users" do
    field(:email, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    cast(user, attrs, [:email])
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

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.SuffixMatchingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "suffix_matching_users" do
    field(:email, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> unique_constraint(:email, name: :email_key, match: :suffix)
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.PrefixMatchingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "prefix_matching_users" do
    field(:email, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> unique_constraint(:email, name: :prefix_matching_users_p0, match: :prefix)
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.RegexMatchingUser do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.CustomSchema

  import Ecto.Changeset

  schema "regex_matching_users" do
    field(:email, :string)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> unique_constraint(:email, name: ~r/^regex_matching_users_p[0-9]+_email_key$/)
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.Repo do
  @doc false
  @spec config() :: keyword()
  def config, do: [otp_app: :bylaw_postgres]
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraints
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.MatchingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.MissingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.PrefixedMissingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.PrefixMatchingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.ProfileOnlyUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.RegexMatchingUser
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.Repo
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraintsTest.SuffixMatchingUser
  alias Bylaw.Db.Issue
  alias Bylaw.Db.Target

  describe "validate/2" do
    test "skips validation without discovery options when disabled" do
      target =
        Postgres.target(
          query: fn _target, _sql, _params, _opts ->
            flunk("query should not run when validation is disabled")
          end
        )

      assert :ok = EctoChangesetUniqueConstraints.validate(target, validate: false)
    end

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

    test "does not apply non-public catalog constraints to an unprefixed schema" do
      target = target([unique("tenant_b", "users", "users_email_index", ["email"])])

      assert :ok =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [MissingUser]
               )
    end

    test "only applies catalog constraints from the schema prefix" do
      target =
        target([
          unique("tenant_a", "prefixed_users", "prefixed_users_email_index", ["email"]),
          unique("tenant_b", "prefixed_users", "prefixed_users_email_index", ["email"])
        ])

      assert {:error, [%Issue{} = issue]} =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [PrefixedMissingUser]
               )

      assert issue.meta.table_schema == "tenant_a"
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

    test "passes with an existing suffix-matched unique helper" do
      target =
        target([
          unique("public", "suffix_matching_users", "suffix_matching_users_p0_email_key", [
            "email"
          ])
        ])

      assert :ok =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [SuffixMatchingUser]
               )
    end

    test "passes with an existing prefix-matched unique helper" do
      target =
        target([
          unique("public", "prefix_matching_users", "prefix_matching_users_p0_email_key", [
            "email"
          ])
        ])

      assert :ok =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [PrefixMatchingUser]
               )
    end

    test "passes with an existing regex-matched unique helper" do
      target =
        target([
          unique("public", "regex_matching_users", "regex_matching_users_p42_email_key", [
            "email"
          ])
        ])

      assert :ok =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [RegexMatchingUser]
               )
    end

    test "returns an issue when catalog introspection fails" do
      target = Postgres.target(query: fn _target, _sql, _params, _opts -> {:error, :closed} end)

      assert {:error, [%Issue{} = issue]} =
               EctoChangesetUniqueConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [MissingUser],
                 rules: [[only: [table: "users"]]]
               )

      assert issue.check == EctoChangesetUniqueConstraints
      assert issue.message == "could not inspect Postgres unique indexes"
      assert issue.target == target
      assert issue.meta.reason == :closed
      assert issue.meta.rules == [%{only: [[table: "users"]], except: []}]
    end

    test "requires keyword options" do
      target = target([])

      assert_raise ArgumentError,
                   "expected ecto_changeset_unique_constraints opts to be a keyword list, got: :bad",
                   fn ->
                     EctoChangesetUniqueConstraints.validate(target, :bad)
                   end
    end

    test "requires a Postgres target" do
      target = %Target{adapter: OtherAdapter}

      assert_raise ArgumentError, ~r/expected a Postgres target/, fn ->
        EctoChangesetUniqueConstraints.validate(target,
          paths: [__ENV__.file],
          schema_modules: [MissingUser]
        )
      end
    end

    test "requires a database target" do
      assert_raise ArgumentError, ~r/expected a database target/, fn ->
        EctoChangesetUniqueConstraints.validate(:not_a_target,
          paths: [__ENV__.file],
          schema_modules: [MissingUser]
        )
      end
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
