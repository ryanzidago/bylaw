defmodule Bylaw.Credo.Check.Ecto.NoRepoPreloadAfterQueryTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Ecto.NoRepoPreloadAfterQuery

  describe "reports issues" do
    test "direct Repo.preload after Repo.all in a query pipeline" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Repo
        alias MyApp.Run

        def bad(status) do
          Run
          |> where([run: r], r.status == ^status)
          |> Repo.all()
          |> Repo.preload([:message])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> assert_issue(%{
        trigger: "Repo.preload",
        message: ~r/Do not call `Repo.preload` after `Repo.one` or `Repo.all`/
      })
    end

    test "direct Repo.preload after Repo.one in a query pipeline" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Repo
        alias MyApp.Run

        def bad(id) do
          Run
          |> where([run: r], r.id == ^id)
          |> Repo.one()
          |> Repo.preload([:message])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> assert_issue(%{
        trigger: "Repo.preload",
        message: ~r/Do not call `Repo.preload` after `Repo.one` or `Repo.all`/
      })
    end

    test "helper-hidden Repo.preload after Repo.one in a query pipeline" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Repo
        alias MyApp.Run

        def bad(id) do
          Run
          |> where([run: r], r.id == ^id)
          |> Repo.one()
          |> preload_run_messages()
        end

        defp preload_run_messages(nil), do: nil

        defp preload_run_messages(run) do
          Repo.preload(run, [:message])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> assert_issue(%{
        trigger: "preload_run_messages",
        message: ~r/Prefer Ecto's query `preload` API/
      })
    end

    test "direct Repo.preload after Repo.one! in a query pipeline" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Repo
        alias MyApp.Run

        def bad(id) do
          Run
          |> where([run: r], r.id == ^id)
          |> Repo.one!()
          |> Repo.preload([:message])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> assert_issue(%{
        trigger: "Repo.preload",
        message: ~r/Do not call `Repo.preload` after `Repo.one` or `Repo.all`/
      })
    end

    test "direct Repo.preload around Repo.one call" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Repo
        alias MyApp.Run

        def bad(id) do
          Repo.preload(
            Run
            |> where([run: r], r.id == ^id)
            |> Repo.one(),
            [:message]
          )
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> assert_issue(%{
        trigger: "Repo.preload",
        message: ~r/Do not call `Repo.preload` after `Repo.one` or `Repo.all`/
      })
    end

    test "direct helper call around Repo.one call" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Repo
        alias MyApp.Run

        def bad(id) do
          preload_run_messages(
            Run
            |> where([run: r], r.id == ^id)
            |> Repo.one()
          )
        end

        defp preload_run_messages(run) do
          Repo.preload(run, [:message])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> assert_issue(%{
        trigger: "preload_run_messages",
        message: ~r/Do not call `Repo.preload` after `Repo.one` or `Repo.all`/
      })
    end
  end

  describe "does not report issues" do
    test "custom query preload before Repo.one stays allowed" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Message
        alias MyApp.Repo
        alias MyApp.Run

        def ok(id) do
          Run
          |> where([run: r], r.id == ^id)
          |> preload(message: ^message_query())
          |> Repo.one()
        end

        defp message_query do
          Message
          |> order_by([message: m], asc: m.inserted_at)
          |> preload([:files])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> refute_issues()
    end

    test "query-time preload before Repo.one" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Repo
        alias MyApp.Run

        def ok(id) do
          Run
          |> where([run: r], r.id == ^id)
          |> preload([:message])
          |> Repo.one()
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> refute_issues()
    end

    test "Repo.preload on an already-loaded function argument" do
      """
      defmodule Example do
        alias MyApp.Repo

        def ok(run) do
          Repo.preload(run, [:message])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> refute_issues()
    end

    test "helper without Repo.preload stays allowed" do
      """
      defmodule Example do
        import Ecto.Query

        alias MyApp.Repo
        alias MyApp.Run

        def ok(id) do
          Run
          |> where([run: r], r.id == ^id)
          |> Repo.one()
          |> wrap_result()
        end

        defp wrap_result(run) do
          {:ok, run}
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> refute_issues()
    end

    test "Repo.preload after Repo.get stays out of scope" do
      """
      defmodule Example do
        alias MyApp.Repo
        alias MyApp.Run

        def ok(id) do
          Repo.get(Run, id)
          |> Repo.preload([:message])
        end
      end
      """
      |> to_source_file("lib/bylaw/example.ex")
      |> run_check(NoRepoPreloadAfterQuery)
      |> refute_issues()
    end
  end
end
