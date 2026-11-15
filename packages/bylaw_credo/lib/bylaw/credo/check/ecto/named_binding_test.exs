defmodule Bylaw.Credo.Check.Ecto.NamedBindingTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.NamedBinding

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
    |> run_check(NamedBinding)
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
    |> run_check(NamedBinding)
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
    |> run_check(NamedBinding)
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
    |> run_check(NamedBinding)
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
    |> run_check(NamedBinding, excluded_paths: ["test/"])
    |> refute_issues()
  end

  test "reports positional bindings piped after from/2" do
    """
    defmodule Example do
      import Ecto.Query

      def run(user_id) do
        from(e in Entry, as: :entry)
        |> where([e], e.user_id == ^user_id)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NamedBinding)
    |> assert_issue(%{line_no: 6})
  end

  test "reports positional bindings later in a pipeline" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query) do
        query
        |> where([entry: e], e.active)
        |> select([e], e.id)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NamedBinding)
    |> assert_issue(%{line_no: 7})
  end

  test "reports a positional binding next to a named one" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query) do
        query
        |> where([entry: e], e.active)
        |> select([l, entry: e], {e.id, l.id})
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NamedBinding)
    |> assert_issue(%{line_no: 7})
  end

  test "reports positional bindings in piped joins" do
    """
    defmodule Example do
      import Ecto.Query

      def run do
        from(e in Entry, as: :entry)
        |> join(:inner, [e], u in assoc(e, :user), as: :user)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NamedBinding)
    |> assert_issue(%{line_no: 6})
  end

  test "reports positional bindings in direct query calls" do
    """
    defmodule Example do
      import Ecto.Query

      def run(query, user_id) do
        query = where(query, [e], e.user_id == ^user_id)
        join(query, :inner, [e], u in assoc(e, :user))
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NamedBinding)
    |> assert_issues(fn issues -> assert Enum.count(issues) == 2 end)
  end

  test "does not report named bindings through a whole pipeline" do
    """
    defmodule Example do
      import Ecto.Query

      def run(token, name) do
        from(t in Token, as: :token)
        |> join(:inner, [token: t], u in assoc(t, :user), as: :user)
        |> where([token: t], t.token == ^token)
        |> where([{^name, x}], is_nil(x.deleted_at))
        |> where(false)
        |> select([token: t, user: u], {u, t})
        |> preload([:user, items: :options])
        |> order_by(desc: :inserted_at)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NamedBinding)
    |> refute_issues()
  end
end
