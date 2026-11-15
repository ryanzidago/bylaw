defmodule Bylaw.Credo.Check.Ecto.PipeBasedQueriesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.PipeBasedQueries

  test "reports keyword clauses passed to from/2" do
    """
    defmodule Example do
      import Ecto.Query

      def query do
        from(u in User, where: u.active, order_by: [asc: u.inserted_at])
      end
    end
    """
    |> to_source_file()
    |> run_check(PipeBasedQueries)
    |> assert_issue(%{
      line_no: 5,
      trigger: "from",
      message: ~r/Use pipe-based Ecto queries/
    })
  end

  test "reports keyword clauses passed to Ecto.Query.from/2" do
    """
    defmodule Example do
      def query do
        Ecto.Query.from(User, where: true)
      end
    end
    """
    |> to_source_file()
    |> run_check(PipeBasedQueries)
    |> assert_issue(%{
      line_no: 3,
      trigger: "Ecto.Query.from",
      message: ~r/Use pipe-based Ecto queries/
    })
  end

  test "does not report pipe-based Ecto queries" do
    """
    defmodule Example do
      import Ecto.Query

      def query do
        User
        |> where([u], u.active)
        |> order_by([u], asc: u.inserted_at)
      end
    end
    """
    |> to_source_file()
    |> run_check(PipeBasedQueries)
    |> refute_issues()
  end

  test "does not report plain from/1 usage" do
    """
    defmodule Example do
      import Ecto.Query

      def query do
        from(u in User)
      end
    end
    """
    |> to_source_file()
    |> run_check(PipeBasedQueries)
    |> refute_issues()
  end

  test "does not report from/2 with only source options" do
    """
    defmodule Example do
      import Ecto.Query

      def query do
        from(r in "vat_rules", prefix: "tax", as: :rule, hints: ["USE INDEX FOO"])
        |> where([rule: r], r.active)
      end
    end
    """
    |> to_source_file()
    |> run_check(PipeBasedQueries)
    |> refute_issues()
  end

  test "reports query clauses next to source options in from/2" do
    """
    defmodule Example do
      import Ecto.Query

      def query do
        from(r in "vat_rules", prefix: "tax", where: r.active)
      end
    end
    """
    |> to_source_file()
    |> run_check(PipeBasedQueries)
    |> assert_issue(%{line_no: 5, trigger: "from"})
  end
end
