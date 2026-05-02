defmodule Bylaw.Credo.Check.Warning.NoRepoTransactionTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Warning.NoRepoTransaction

  test "reports Repo.transaction" do
    """
    defmodule Example do
      def run do
        Repo.transaction(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoRepoTransaction)
    |> assert_issue()
  end

  test "does not report Repo.transact" do
    """
    defmodule Example do
      def run do
        Repo.transact(fn -> :ok end)
      end
    end
    """
    |> to_source_file()
    |> run_check(NoRepoTransaction)
    |> refute_issues()
  end
end
