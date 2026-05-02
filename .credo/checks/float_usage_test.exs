defmodule Bylaw.Credo.Check.Warning.FloatUsageTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Warning.FloatUsage

  test "reports float column types in migrations" do
    """
    defmodule Example.Repo.Migrations.AddAmounts do
      use Ecto.Migration

      def change do
        create table(:orders) do
          add :total, :float
        end

        alter table(:orders) do
          modify :tax_rate, :float
          add_if_not_exists :fee, :float
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(FloatUsage)
    |> assert_issues(3)
    |> assert_issues_match([
      %{
        line_no: 6,
        trigger: "add",
        message: ~r/Prefer `:decimal` over `:float` in Ecto migrations/
      },
      %{
        line_no: 10,
        trigger: "modify",
        message: ~r/Prefer `:decimal` over `:float` in Ecto migrations/
      },
      %{
        line_no: 11,
        trigger: "add_if_not_exists",
        message: ~r/Prefer `:decimal` over `:float` in Ecto migrations/
      }
    ])
  end

  test "reports float field types in schemas" do
    """
    defmodule Example.Order do
      use Ecto.Schema

      schema "orders" do
        field :total, :float
      end
    end
    """
    |> to_source_file()
    |> run_check(FloatUsage)
    |> assert_issue(%{
      line_no: 5,
      trigger: "field",
      message: ~r/Prefer `:decimal` over `:float` in Ecto schemas/
    })
  end

  test "reports Float module calls, float literals, and float typespecs" do
    """
    defmodule Example.Amount do
      @spec rounded_amount() :: float()
      def rounded_amount do
        rounded = Float.round(1.25, 2)
        fallback = 9.99
        {rounded, fallback}
      end
    end
    """
    |> to_source_file()
    |> run_check(FloatUsage)
    |> assert_issues(3)
    |> assert_issues_match([
      %{line_no: 2, trigger: "float()", message: ~r/Prefer `Decimal\.t\(\)` over `float\(\)`/},
      %{
        line_no: 4,
        trigger: "Float.round",
        message: ~r/Prefer `Decimal` APIs over the `Float` module/
      },
      %{line_no: 5, trigger: "9.99", message: ~r/Prefer `Decimal\.new\/1` over float literals/}
    ])
  end

  test "does not report Decimal usage" do
    """
    defmodule Example.Order do
      use Ecto.Schema
      import Ecto.Query

      schema "orders" do
        field :total, :decimal
      end

      def rounded_amount(value) do
        Decimal.round(value, 2)
      end

      @spec default_amount() :: Decimal.t()
      def default_amount, do: Decimal.new("9.99")
    end

    defmodule Example.Repo.Migrations.AddAmounts do
      use Ecto.Migration

      def change do
        create table(:orders) do
          add :total, :decimal
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(FloatUsage)
    |> refute_issues()
  end
end
