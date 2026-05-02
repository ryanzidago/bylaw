defmodule Bylaw.Credo.Check.Warning.NoRepoMutationInLoopTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Warning.NoRepoMutationInLoop

  test "reports Repo.update inside Enum.reduce_while outside a transaction" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.reduce_while(changesets, :ok, fn changeset, :ok ->
          case Repo.update(changeset) do
            {:ok, _record} -> {:cont, :ok}
            {:error, reason} -> {:halt, {:error, reason}}
          end
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.update"
    end)
  end

  test "reports Repo.update capture inside Enum.map outside a transaction" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.map(changesets, &Repo.update/1)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.update"
    end)
  end

  test "reports Repo.insert inside a for comprehension outside a transaction" do
    """
    defmodule Example do
      def run(changesets) do
        for changeset <- changesets do
          Repo.insert(changeset)
        end
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.insert"
    end)
  end

  test "reports Repo.insert! inside Enum.each outside a transaction" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.each(changesets, fn changeset ->
          Repo.insert!(changeset)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.insert!"
    end)
  end

  test "reports Repo.insert_or_update inside Enum.each outside a transaction" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.each(changesets, fn changeset ->
          Repo.insert_or_update(changeset)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.insert_or_update"
    end)
  end

  test "reports Repo.insert_or_update! inside Enum.each outside a transaction" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.each(changesets, fn changeset ->
          Repo.insert_or_update!(changeset)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.insert_or_update!"
    end)
  end

  test "reports Repo.delete_all inside Enum.each outside a transaction" do
    """
    defmodule Example do
      def run(queries) do
        Enum.each(queries, fn query ->
          Repo.delete_all(query)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.delete_all"
    end)
  end

  test "reports Repo.update_all inside nested logic under a loop" do
    """
    defmodule Example do
      def run(queries) do
        Enum.each(queries, fn query ->
          if query do
            Repo.update_all(query, set: [status: :done])
          end
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.update_all"
    end)
  end

  test "still reports when each iteration opens its own transaction" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.each(changesets, fn changeset ->
          Repo.transact(fn ->
            Repo.update(changeset)
          end)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.update"
    end)
  end

  test "reports Repo.delete inside a nested inner loop outside a transaction" do
    """
    defmodule Example do
      def run(groups) do
        Enum.each(groups, fn changesets ->
          Enum.each(changesets, fn changeset ->
            Repo.delete(changeset)
          end)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.delete"
    end)
  end

  test "does not report writes when the loop is inside Repo.transact" do
    """
    defmodule Example do
      def run(changesets) do
        Repo.transact(fn ->
          Enum.each(changesets, fn changeset ->
            Repo.update(changeset)
          end)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report nested loops when the outer loop is inside Repo.transact" do
    """
    defmodule Example do
      def run(groups) do
        Repo.transact(fn ->
          Enum.each(groups, fn changesets ->
            Enum.each(changesets, fn changeset ->
              Repo.update(changeset)
            end)
          end)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report writes when the loop is inside Repo.transaction" do
    """
    defmodule Example do
      def run(changesets) do
        Repo.transaction(fn ->
          Enum.each(changesets, fn changeset ->
            Repo.update(changeset)
          end)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report direct Repo mutation calls outside loops" do
    """
    defmodule Example do
      def run(changeset) do
        Repo.update(changeset)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report read-only Repo calls inside loops" do
    """
    defmodule Example do
      def run(queries) do
        Enum.each(queries, fn query ->
          Repo.all(query)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report Enum calls without callbacks" do
    """
    defmodule Example do
      def run(values) do
        Enum.sum(values)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report Ecto.Multi operations built in a loop" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.reduce(changesets, Ecto.Multi.new(), fn changeset, multi ->
          Ecto.Multi.update(multi, :item, changeset)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report non-Repo function captures inside loops" do
    """
    defmodule Example do
      def run(values) do
        Enum.map(values, &Integer.to_string/1)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report deferred anonymous functions built inside loops" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.map(changesets, fn changeset ->
          fn -> Repo.update(changeset) end
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report Ecto.Multi.run callbacks built inside loops" do
    """
    defmodule Example do
      def run(changesets) do
        Enum.reduce(changesets, Ecto.Multi.new(), fn changeset, multi ->
          Ecto.Multi.run(multi, {:item, changeset.id}, fn _repo, _changes ->
            Repo.update(changeset)
          end)
        end)
      end
    end
    """
    |> to_source_file("lib/bylaw/example.ex")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "does not report files under excluded test paths" do
    """
    defmodule ExampleTest do
      def run(changesets) do
        Enum.each(changesets, fn changeset ->
          Repo.update(changeset)
        end)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoRepoMutationInLoop)
    |> refute_issues()
  end

  test "can override excluded_paths and report test files when requested" do
    """
    defmodule ExampleTest do
      def run(changesets) do
        Enum.each(changesets, fn changeset ->
          Repo.update(changeset)
        end)
      end
    end
    """
    |> to_source_file("test/example_test.exs")
    |> run_check(NoRepoMutationInLoop, excluded_paths: [])
    |> assert_issue(fn issue ->
      assert issue.trigger == "Repo.update"
    end)
  end
end
