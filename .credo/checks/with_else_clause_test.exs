defmodule Bylaw.Credo.Check.Readability.WithElseClauseTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Readability.WithElseClause

  test "reports with expressions without else clauses" do
    """
    defmodule Example do
      def call(id) do
        with {:ok, user} <- fetch_user(id),
             {:ok, account} <- fetch_account(user) do
          {:ok, account}
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseClause)
    |> assert_issue(%{
      line_no: 3,
      trigger: "with",
      message: ~r/Add an `else` clause/
    })
  end

  test "does not report with expressions with else clauses" do
    """
    defmodule Example do
      def call(id) do
        with {:ok, user} <- fetch_user(id),
             {:ok, account} <- fetch_account(user) do
          {:ok, account}
        else
          error -> error
        end
      end
    end
    """
    |> to_source_file()
    |> run_check(WithElseClause)
    |> refute_issues()
  end
end
