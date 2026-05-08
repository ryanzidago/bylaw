defmodule Bylaw.Credo.Check.Phoenix.NoRepoInControllerTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Phoenix.NoRepoInController

  test "reports Repo.get in a controller file" do
    """
    defmodule MyAppWeb.ThingController do
      def show(conn, %{"id" => id}) do
        Repo.get!(Thing, id)
      end
    end
    """
    |> to_source_file("lib/my_app_web/controllers/thing_controller.ex")
    |> run_check(NoRepoInController)
    |> assert_issue()
  end

  test "reports Repo.all in a controller file" do
    """
    defmodule MyAppWeb.ThingController do
      def index(conn, _params) do
        Repo.all(Thing)
      end
    end
    """
    |> to_source_file("lib/my_app_web/controllers/thing_controller.ex")
    |> run_check(NoRepoInController)
    |> assert_issue()
  end

  test "reports fully qualified Bylaw.Repo call" do
    """
    defmodule MyAppWeb.ThingController do
      def show(conn, %{"id" => id}) do
        Bylaw.Repo.get(Thing, id)
      end
    end
    """
    |> to_source_file("lib/my_app_web/controllers/thing_controller.ex")
    |> run_check(NoRepoInController)
    |> assert_issue()
  end

  test "does not report Repo in a non-controller file" do
    """
    defmodule MyApp.Things do
      def get_thing!(id) do
        Repo.get!(Thing, id)
      end
    end
    """
    |> to_source_file("lib/my_app/things.ex")
    |> run_check(NoRepoInController)
    |> refute_issues()
  end

  test "does not report Repo in a controller test file" do
    """
    defmodule MyAppWeb.ThingControllerTest do
      def setup do
        Repo.insert!(%Thing{name: "test"})
      end
    end
    """
    |> to_source_file("lib/my_app_web/controllers/thing_controller_test.exs")
    |> run_check(NoRepoInController)
    |> refute_issues()
  end

  test "does not report non-Repo module calls in a controller" do
    """
    defmodule MyAppWeb.ThingController do
      def index(conn, _params) do
        Things.list_things()
      end
    end
    """
    |> to_source_file("lib/my_app_web/controllers/thing_controller.ex")
    |> run_check(NoRepoInController)
    |> refute_issues()
  end
end
