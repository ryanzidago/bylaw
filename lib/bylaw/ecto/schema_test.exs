defmodule Bylaw.Ecto.SchemaTest.CustomSchema do
  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema

      @primary_key false
    end
  end
end

defmodule Bylaw.Ecto.SchemaTest.Account do
  use Bylaw.Ecto.SchemaTest.CustomSchema

  schema "accounts" do
    field(:name, :string)
  end
end

defmodule Bylaw.Ecto.SchemaTest.User do
  use Bylaw.Ecto.SchemaTest.CustomSchema

  alias Bylaw.Ecto.SchemaTest.Account

  schema "users" do
    field(:email, :string)
    field(:name, :string)
    belongs_to(:account, Account)
  end
end

defmodule Bylaw.Ecto.SchemaTest do
  use ExUnit.Case, async: true

  alias Bylaw.Ecto.Schema
  alias Bylaw.Ecto.SchemaTest.User

  describe "ecto_schema?/1" do
    test "detects Ecto schemas compiled through custom wrapper macros" do
      assert Schema.ecto_schema?(User)
    end
  end

  describe "info/1" do
    test "returns compiled schema metadata" do
      assert Schema.info(User) == %{
               module: User,
               source: "users",
               prefix: nil,
               fields: [:email, :name, :account_id],
               associations: [:account],
               field_sources: %{
                 "account_id" => :account_id,
                 "email" => :email,
                 "name" => :name
               }
             }
    end
  end
end
