defmodule Bylaw.Ecto.ChangesetTest.CustomSchema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key false
    end
  end
end

defmodule Bylaw.Ecto.ChangesetTest.Account do
  use Bylaw.Ecto.ChangesetTest.CustomSchema

  schema "accounts" do
    field(:name, :string)
  end
end

defmodule Bylaw.Ecto.ChangesetTest.User do
  use Bylaw.Ecto.ChangesetTest.CustomSchema

  import Ecto.Changeset

  alias Bylaw.Ecto.ChangesetTest.Account

  schema "users" do
    field(:email, :string)
    field(:name, :string)
    belongs_to(:account, Account)
  end

  @doc false
  @spec registration_changeset(struct(), map()) :: Ecto.Changeset.struct()
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :account_id])
    |> unique_constraint(:email, name: :users_email_index)
    |> foreign_key_constraint(:account_id)
  end

  @doc false
  @spec partition_changeset(struct(), map()) :: Ecto.Changeset.struct()
  def partition_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> unique_constraint(:email, name: :email_key, match: :suffix)
    |> unique_constraint(:email, name: ~r/^users_p[0-9]+_email_key$/)
  end

  @doc false
  @spec profile_changeset(struct(), map()) :: Ecto.Changeset.struct()
  def profile_changeset(user, attrs) do
    Ecto.Changeset.cast(user, attrs, [:name])
  end

  @doc false
  @spec change_changeset(struct()) :: Ecto.Changeset.struct()
  def change_changeset(user) do
    change(user, %{email: "updated@example.com"})
  end

  @doc false
  @spec dynamic_changeset(struct(), map(), list(atom())) :: Ecto.Changeset.struct()
  def dynamic_changeset(user, attrs, fields) do
    cast(user, attrs, fields)
  end
end

defmodule Bylaw.Ecto.ChangesetTest do
  use ExUnit.Case, async: true

  alias Bylaw.Ecto.Changeset
  alias Bylaw.Ecto.ChangesetTest.User

  describe "candidates/2" do
    test "extracts candidate functions using cast and change with literal fields" do
      candidates = Changeset.candidates([__ENV__.file], [User])

      assert Enum.map(candidates, &{&1.function, &1.arity, &1.fields}) == [
               {:change_changeset, 1, [:email]},
               {:partition_changeset, 2, [:email]},
               {:profile_changeset, 2, [:name]},
               {:registration_changeset, 2, [:account_id, :email]}
             ]
    end

    test "extracts direct changeset constraint helper calls" do
      [candidate] =
        __ENV__.file
        |> List.wrap()
        |> Changeset.candidates([User])
        |> Enum.filter(&(&1.function == :registration_changeset))

      assert Enum.map(candidate.constraints, &{&1.kind, &1.fields, &1.name}) == [
               {:unique, [:email], "users_email_index"},
               {:foreign_key, [:account_id], nil}
             ]
    end

    test "extracts constraint name match modes and literal regex names" do
      [candidate] =
        __ENV__.file
        |> List.wrap()
        |> Changeset.candidates([User])
        |> Enum.filter(&(&1.function == :partition_changeset))

      assert [
               %{kind: :unique, fields: [:email], name: "email_key", match: :suffix},
               %{kind: :unique, fields: [:email], name: regex, match: :exact}
             ] = candidate.constraints

      assert Regex.match?(regex, "users_p12_email_key")
    end
  end
end
