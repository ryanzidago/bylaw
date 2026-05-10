defmodule Bylaw.Credo.Check.Ecto.UseMyAppSchemaTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.UseMyAppSchema

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
    |> run_check(UseMyAppSchema)
    |> assert_issue()
    |> assert_issues_match([
      %{
        line_no: 2,
        trigger: "use Ecto.Schema",
        message:
          "Use your app schema module, such as `use MyApp.Schema`, instead of `use Ecto.Schema`."
      }
    ])
  end

  test "does not report use MyApp.Schema" do
    """
    defmodule Bylaw.Accounts.User do
      use MyApp.Schema

      schema "users" do
        field :email, :string
      end
    end
    """
    |> to_source_file("lib/bylaw/accounts/user.ex")
    |> run_check(UseMyAppSchema)
    |> refute_issues()
  end

  test "does not report the app schema module itself" do
    """
    defmodule MyApp.Schema do
      defmacro __using__(_opts) do
        quote do
          use Ecto.Schema
        end
      end
    end
    """
    |> to_source_file("lib/acme/schema.ex")
    |> run_check(UseMyAppSchema)
    |> refute_issues()
  end
end
