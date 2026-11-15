defmodule Bylaw.Credo.Check.Phoenix.NoRepoInWebTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Phoenix.NoRepoInWeb

  test "reports Repo.all in a LiveView" do
    """
    defmodule MyAppWeb.ThingLive.Index do
      def mount(_params, _session, socket) do
        {:ok, assign(socket, :things, Repo.all(Thing))}
      end
    end
    """
    |> to_source_file("lib/my_app_web/live/thing_live/index.ex")
    |> run_check(NoRepoInWeb)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Do not call `Repo` from web code"
      assert issue.line_no == 3
    end)
  end

  test "reports a fully qualified MyApp.Repo.get in a function component module" do
    """
    defmodule MyAppWeb.CoreComponents do
      def thing_name(assigns) do
        thing = MyApp.Repo.get(Thing, assigns.id)
        thing.name
      end
    end
    """
    |> to_source_file("lib/my_app_web/components/core_components.ex")
    |> run_check(NoRepoInWeb)
    |> assert_issue()
  end

  test "reports a Repo call through an alias with as:" do
    """
    defmodule MyAppWeb.ThingLive.Show do
      alias MyApp.Repo, as: Store

      def mount(%{"id" => id}, _session, socket) do
        {:ok, assign(socket, :thing, Store.get!(Thing, id))}
      end
    end
    """
    |> to_source_file("lib/my_app_web/live/thing_live/show.ex")
    |> run_check(NoRepoInWeb)
    |> assert_issue()
  end

  test "reports a Repo call in a controller" do
    """
    defmodule MyAppWeb.ThingController do
      def show(conn, %{"id" => id}) do
        render(conn, :show, thing: Repo.get!(Thing, id))
      end
    end
    """
    |> to_source_file("lib/my_app_web/controllers/thing_controller.ex")
    |> run_check(NoRepoInWeb)
    |> assert_issue()
  end

  test "reports import Ecto.Query in a LiveView" do
    """
    defmodule MyAppWeb.ThingLive.Index do
      import Ecto.Query

      def mount(_params, _session, socket) do
        {:ok, assign(socket, :query, from(t in Thing))}
      end
    end
    """
    |> to_source_file("lib/my_app_web/live/thing_live/index.ex")
    |> run_check(NoRepoInWeb)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Build queries in a context or core module"
      assert issue.line_no == 2
    end)
  end

  test "reports alias Ecto.Query in a LiveView" do
    """
    defmodule MyAppWeb.ThingLive.Index do
      alias Ecto.Query
    end
    """
    |> to_source_file("lib/my_app_web/live/thing_live/index.ex")
    |> run_check(NoRepoInWeb)
    |> assert_issue(fn issue ->
      assert issue.message =~ "Build queries in a context or core module"
    end)
  end

  test "reports Ecto.Query inside a multi-alias" do
    """
    defmodule MyAppWeb.ThingLive.Index do
      alias Ecto.{Changeset, Query}
    end
    """
    |> to_source_file("lib/my_app_web/live/thing_live/index.ex")
    |> run_check(NoRepoInWeb)
    |> assert_issue()
  end

  test "reports an Ecto.Query.from call" do
    """
    defmodule MyAppWeb.ThingLive.Index do
      require Ecto.Query

      def mount(_params, _session, socket) do
        {:ok, assign(socket, :query, Ecto.Query.from(t in Thing))}
      end
    end
    """
    |> to_source_file("lib/my_app_web/live/thing_live/index.ex")
    |> run_check(NoRepoInWeb)
    |> assert_issue(fn issue -> assert issue.line_no == 5 end)
  end

  test "does not report Ecto.Changeset in a LiveView" do
    """
    defmodule MyAppWeb.ThingLive.Form do
      import Ecto.Changeset
      alias Ecto.Changeset

      def handle_event("validate", params, socket) do
        changeset = Changeset.change(%Thing{}, params)
        {:noreply, assign(socket, :form, to_form(add_error(changeset, :name, "bad")))}
      end
    end
    """
    |> to_source_file("lib/my_app_web/live/thing_live/form.ex")
    |> run_check(NoRepoInWeb)
    |> refute_issues()
  end

  test "does not report context calls in a LiveView" do
    """
    defmodule MyAppWeb.ThingLive.Index do
      alias MyApp.Core.Things

      def mount(_params, _session, socket) do
        {:ok, assign(socket, :things, Things.list_things())}
      end
    end
    """
    |> to_source_file("lib/my_app_web/live/thing_live/index.ex")
    |> run_check(NoRepoInWeb)
    |> refute_issues()
  end

  test "does not report Repo outside the web layer" do
    """
    defmodule MyApp.Things do
      import Ecto.Query

      def list_things, do: Repo.all(from(t in Thing))
    end
    """
    |> to_source_file("lib/my_app/things.ex")
    |> run_check(NoRepoInWeb)
    |> refute_issues()
  end

  test "does not report Repo in a web test file" do
    """
    defmodule MyAppWeb.ThingLiveTest do
      test "lists things" do
        Repo.insert!(%Thing{name: "test"})
      end
    end
    """
    |> to_source_file("test/my_app_web/live/thing_live_test.exs")
    |> run_check(NoRepoInWeb)
    |> refute_issues()
  end

  test "checks only the configured paths" do
    source = """
    defmodule MyAppWeb.ThingLive.Index do
      def mount(_params, _session, socket) do
        {:ok, assign(socket, :things, Repo.all(Thing))}
      end
    end
    """

    source
    |> to_source_file("lib/admin_web/live/thing_live/index.ex")
    |> run_check(NoRepoInWeb, paths: ["lib/my_app_web/"])
    |> refute_issues()

    source
    |> to_source_file("lib/my_app_web/live/thing_live/index.ex")
    |> run_check(NoRepoInWeb, paths: ["lib/my_app_web/"])
    |> assert_issue()
  end

  test "skips excluded paths" do
    """
    defmodule MyAppWeb.HealthController do
      def show(conn, _params) do
        Repo.query!("SELECT 1")
        send_resp(conn, 200, "ok")
      end
    end
    """
    |> to_source_file("lib/my_app_web/controllers/health_controller.ex")
    |> run_check(NoRepoInWeb, excluded_paths: ["/health_controller.ex"])
    |> refute_issues()
  end
end
