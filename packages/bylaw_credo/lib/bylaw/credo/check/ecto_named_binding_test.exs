defmodule Bylaw.Credo.Check.EctoNamedBindingTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.EctoNamedBinding

  test "reports schema pipes with positional bindings" do
    """
    defmodule Example do
      import Ecto.Query

      def run(user_id) do
        Entry
        |> where([e], e.user_id == ^user_id)
        |> Repo.all()
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(EctoNamedBinding)
    |> assert_issue()
  end

  test "reports query variables with positional bindings" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query) do
        query
        |> where([e], e.active == true)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(EctoNamedBinding)
    |> assert_issue()
  end

  test "reports query variables with multi-char positional bindings" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query) do
        query
        |> where([wu], wu.active == true)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(EctoNamedBinding)
    |> assert_issue()
  end

  test "does not report named bindings" do
    """
    defmodule Example do
      import Ecto.Query

      def run(user_id) do
        from(e in Entry, as: :entry)
        |> where([entry: e], e.user_id == ^user_id)
        |> Repo.all()
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(EctoNamedBinding)
    |> refute_issues()
  end

  test "respects excluded paths" do
    """
    defmodule ExampleTest do
      import Ecto.Query

      def run(query) do
        query
        |> where([e], e.active == true)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(EctoNamedBinding, excluded_paths: ["test/"])
    |> refute_issues()
  end
end
