defmodule Bylaw.Credo.Check.NoAndInEctoWhereTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.NoAndInEctoWhere

  test "reports and inside piped Ecto where clauses" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query, workspace_id, status) do
        query
        |> where([w], w.workspace_id == ^workspace_id and w.status == ^status)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoAndInEctoWhere)
    |> assert_issue(%{
      line_no: 6,
      trigger: "and",
      message: ~r/Do not use `and` inside Ecto `where` clauses/
    })
  end

  test "reports and inside from where clauses" do
    """
    defmodule Example do
      import Ecto.Query

      def run(workspace_id, status) do
        from(w in Workspace, where: w.workspace_id == ^workspace_id and w.status == ^status)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoAndInEctoWhere)
    |> assert_issue(%{
      line_no: 5,
      trigger: "and",
      message: ~r/Do not use `and` inside Ecto `where` clauses/
    })
  end

  test "does not report separate where clauses" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query, workspace_id, status) do
        query
        |> where([w], w.workspace_id == ^workspace_id)
        |> where([w], w.status == ^status)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoAndInEctoWhere)
    |> refute_issues()
  end

  test "does not report ordinary boolean expressions outside Ecto where" do
    """
    defmodule Example do
      def run(left, right) do
        left and right
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoAndInEctoWhere)
    |> refute_issues()
  end
end
