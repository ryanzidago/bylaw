defmodule Bylaw.Credo.Check.Ecto.NoRepoInLoopTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.NoRepoInLoop

  defp triggers(source, params \\ [], filename \\ "lib/my_app/sample.ex") do
    source
    |> to_source_file(filename)
    |> run_check(NoRepoInLoop, params)
    |> Enum.map(&{&1.line_no, &1.trigger})
  end

  test "reports repo calls in Enum and Stream callbacks, through aliases" do
    source = """
    defmodule MyApp.Sample do
      alias MyApp.Repo, as: DB

      def load(ids) do
        Enum.map(ids, fn id -> MyApp.Repo.get(Item, id) end)
        ids |> Stream.map(&DB.get(Item, &1)) |> Enum.to_list()
        Enum.each(ids, &MyApp.Repo.delete/1)
      end
    end
    """

    assert triggers(source) == [
             {5, "MyApp.Repo.get"},
             {6, "MyApp.Repo.get"},
             {7, "MyApp.Repo.delete"}
           ]
  end

  test "reports repo calls in Task.async_stream but not in a single Task.async" do
    source = """
    defmodule MyApp.Sample do
      alias MyApp.Repo

      def load(ids) do
        Task.async_stream(ids, fn id -> Repo.get(Item, id) end)
        Task.async(fn -> Repo.all(Item) end)
      end
    end
    """

    assert triggers(source) == [{5, "MyApp.Repo.get"}]
  end

  test "follows the module's own functions that call the repo" do
    source = """
    defmodule MyApp.Sample do
      alias MyApp.Repo

      def save(rows), do: Enum.each(rows, &insert/1)
      def save_all(rows), do: Enum.map(rows, fn row -> wrap(row) end)
      def names(rows), do: Enum.map(rows, &name/1)

      defp wrap(row), do: insert(row)
      defp insert(row), do: Repo.insert(row)
      defp name(row), do: row.name
    end
    """

    assert triggers(source) == [{4, "insert"}, {5, "wrap"}]
  end

  test "reports for bodies, filters and later generators, not the first generator" do
    source = """
    defmodule MyApp.Sample do
      alias MyApp.Repo

      def run(query, ids) do
        for item <- Repo.all(query), do: item.name
        for id <- ids, do: Repo.get(Item, id)
        for id <- ids, Repo.exists?(Item), do: id
        for id <- ids, item <- Repo.all(Item), do: {id, item}
      end
    end
    """

    assert triggers(source) == [
             {6, "MyApp.Repo.get"},
             {7, "MyApp.Repo.exists?"},
             {8, "MyApp.Repo.all"}
           ]
  end

  test "does not report repo calls outside loops or loops without repo calls" do
    """
    defmodule MyApp.Sample do
      alias MyApp.Repo

      def run(ids) do
        items = Repo.all(from i in Item, where: i.id in ^ids)
        Repo.insert_all(Item, Enum.map(items, &Map.take(&1, [:name])))
        Repo.transact(fn -> {:ok, Enum.map(items, & &1.name)} end)
      end
    end
    """
    |> to_source_file("lib/my_app/sample.ex")
    |> run_check(NoRepoInLoop)
    |> refute_issues()
  end

  test "treats any module ending in Repo as a repo unless repo_modules is given" do
    source = """
    defmodule MyApp.Sample do
      def run(ids) do
        Enum.map(ids, &MyApp.Repo.get(Item, &1))
        Enum.map(ids, &MyApp.ReadRepo.get(Item, &1))
      end
    end
    """

    assert triggers(source) == [{3, "MyApp.Repo.get"}]
    assert triggers(source, repo_modules: [MyApp.ReadRepo]) == [{4, "MyApp.ReadRepo.get"}]
  end

  test "reports repo calls in configured loop functions and loop modules" do
    source = """
    defmodule MyApp.Sample do
      alias MyApp.Pricing
      alias MyApp.Repo

      def save(rows) do
        Pricing.collect(rows, &Repo.insert/1)
        Pricing.total(rows, &Repo.insert/1)
        MyApp.Batches.each(rows, &Repo.insert/1)
      end
    end
    """

    assert triggers(source) == []

    assert triggers(source, loop_functions: [{MyApp.Pricing, [:collect]}]) == [
             {6, "MyApp.Repo.insert"}
           ]

    assert triggers(source, loop_modules: [MyApp.Batches]) == [{8, "MyApp.Repo.insert"}]
  end

  test "checks only files in included_paths and outside excluded_paths" do
    source = """
    defmodule MyApp.Sample do
      def load(ids), do: Enum.map(ids, &MyApp.Repo.get(Item, &1))
    end
    """

    assert triggers(source, [], "test/my_app/sample_test.exs") == []

    assert triggers(source, [included_paths: ["test/"]], "test/my_app/sample_test.exs") == [
             {2, "MyApp.Repo.get"}
           ]

    assert triggers(source, [excluded_paths: [~r"/import/"]], "lib/my_app/import/menu.ex") ==
             []
  end
end
