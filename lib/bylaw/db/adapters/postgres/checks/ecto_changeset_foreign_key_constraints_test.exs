defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.CustomSchema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key false
    end
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.Account do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.CustomSchema

  schema "accounts" do
    field(:name, :string)
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.MissingMember do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.CustomSchema

  import Ecto.Changeset

  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.Account

  schema "members" do
    belongs_to(:account, Account)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(member, attrs) do
    cast(member, attrs, [:account_id])
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.MatchingMember do
  use Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.CustomSchema

  import Ecto.Changeset

  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.Account

  schema "matching_members" do
    belongs_to(:account, Account)
  end

  @doc false
  @spec changeset(struct(), map()) :: Ecto.Changeset.struct()
  def changeset(member, attrs) do
    member
    |> cast(attrs, [:account_id])
    |> foreign_key_constraint(:account_id, name: "matching_members_account_id_fkey")
  end
end

defmodule Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest do
  use ExUnit.Case, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.MatchingMember
  alias Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraintsTest.MissingMember
  alias Bylaw.Db.Issue

  describe "validate/2" do
    test "reports a missing foreign_key_constraint for a cast foreign key field" do
      target =
        target([foreign_key("public", "members", "members_account_id_fkey", ["account_id"])])

      assert {:error, [%Issue{} = issue]} =
               EctoChangesetForeignKeyConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [MissingMember]
               )

      assert issue.check == EctoChangesetForeignKeyConstraints
      assert issue.message =~ "#{inspect(MissingMember)}.changeset/2"
      assert issue.message =~ ~s/casts :account_id for table "members"/

      assert issue.message =~ ~s/Postgres has foreign key constraint "members_account_id_fkey"/
      assert issue.message =~ "does not declare foreign_key_constraint(:account_id)"
      assert issue.meta.constraint_kind == :foreign_key
      assert issue.meta.fields == [:account_id]
    end

    test "passes with an existing explicit foreign key helper" do
      target =
        target([
          foreign_key(
            "public",
            "matching_members",
            "matching_members_account_id_fkey",
            ["account_id"]
          )
        ])

      assert :ok =
               EctoChangesetForeignKeyConstraints.validate(target,
                 paths: [__ENV__.file],
                 schema_modules: [MatchingMember]
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

  defp foreign_key(schema, table, name, columns), do: [schema, table, name, columns]
end
