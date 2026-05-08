defmodule Bylaw.Credo.Check.Ecto.UseBylawSchemaTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.UseBylawSchema

  test "reports use Ecto.Schema in application schemas" do
    """
    defmodule Bylaw.Accounts.User do
      use Ecto.Schema

      schema "users" do
        field :email, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/accounts/user.ex")
    |> run_check(UseBylawSchema)
    |> assert_issue()
    |> assert_issues_match([
      %{
        line_no: 2,
        trigger: "use Ecto.Schema",
        message: "Use `use Bylaw.Schema` instead of `use Ecto.Schema`."
      }
    ])
  end

  test "does not report use Bylaw.Schema" do
    """
    defmodule Bylaw.Accounts.User do
      use Bylaw.Schema

      schema "users" do
        field :email, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/accounts/user.ex")
    |> run_check(UseBylawSchema)
    |> refute_issues()
  end

  test "does not report Bylaw.Schema itself" do
    """
    defmodule Bylaw.Schema do
      defmacro __using__(_opts) do
        quote do
          use Ecto.Schema
        end
      end
    end
    """
    |> to_source_file("lib/bylaw/schema.ex")
    |> run_check(UseBylawSchema)
    |> refute_issues()
  end
end
