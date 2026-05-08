defmodule Bylaw.Credo.Check.UseVerifiedRoutesTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.UseVerifiedRoutes

  test "reports direct request helper paths in ConnCase tests" do
    """
    defmodule BylawWeb.Api.V1.OpenApiTest do
      use BylawWeb.ConnCase, async: true

      test "fetches the spec", %{conn: conn} do
        conn |> get("/api/v1/openapi")
      end
    end
    """
    |> to_source_file("lib/bylaw_web/api/v1/openapi_test.exs")
    |> run_check(UseVerifiedRoutes)
    |> assert_issue(%{line_no: 5, trigger: "/api/v1/openapi"})
  end

  test "does not report verified routes in ConnCase tests" do
    """
    defmodule BylawWeb.Api.V1.OpenApiTest do
      use BylawWeb.ConnCase, async: true

      test "fetches the spec", %{conn: conn} do
        conn |> get(~p"/api/v1/openapi")
      end
    end
    """
    |> to_source_file("lib/bylaw_web/api/v1/openapi_test.exs")
    |> run_check(UseVerifiedRoutes)
    |> refute_issues()
  end

  test "reports route helper functions that return interpolated paths" do
    """
    defmodule BylawWeb.Api.V1.WorkspaceController do
      use BylawWeb, :controller

      defp workspace_path(tenant_id, workspace_id) do
        "/api/v1/tenants/\#{tenant_id}/workspaces/\#{workspace_id}"
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/workspace_controller.ex")
    |> run_check(UseVerifiedRoutes)
    |> assert_issue(%{line_no: 4, trigger: "workspace_path"})
  end

  test "reports route location helpers that return interpolated paths" do
    """
    defmodule BylawWeb.Api.V1.MessageController do
      use BylawWeb, :controller

      defp run_location(tenant_id, workspace_id, run_id) do
        "/api/v1/tenants/\#{tenant_id}/workspaces/\#{workspace_id}/runs/\#{run_id}"
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/message_controller.ex")
    |> run_check(UseVerifiedRoutes)
    |> assert_issue(%{line_no: 4, trigger: "run_location"})
  end

  test "reports route string comparisons" do
    """
    defmodule BylawWeb.Api.V1.MessageControllerTest do
      use BylawWeb.ConnCase, async: true

      test "asserts location", %{conn: conn} do
        assert get_resp_header(conn, "location") == [
                 "/api/v1/tenants/\#{tenant_id}/workspaces/\#{workspace_id}"
               ]
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/message_controller_test.exs")
    |> run_check(UseVerifiedRoutes)
    |> assert_issue(%{line_no: 5})
  end

  test "does not report comparisons that already use verified routes" do
    """
    defmodule BylawWeb.Api.V1.MessageControllerTest do
      use BylawWeb.ConnCase, async: true

      test "asserts location", %{conn: conn} do
        assert location == ~p"/api/v1/tenants/\#{tenant_id}/workspaces/\#{workspace_id}"
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/message_controller_test.exs")
    |> run_check(UseVerifiedRoutes)
    |> refute_issues()
  end

  test "ignores HEEx route attributes for now" do
    """
    defmodule BylawWeb.Layouts do
      use BylawWeb, :html

      def app(assigns) do
        ~H\"\"\"
        <a href="/">Home</a>
        \"\"\"
      end
    end
    """
    |> to_source_file("lib/bylaw_web/components/layouts.ex")
    |> run_check(UseVerifiedRoutes)
    |> refute_issues()
  end

  test "does not report verified routes with query maps in ConnCase tests" do
    """
    defmodule BylawWeb.Api.V1.WorkspaceControllerTest do
      use BylawWeb.ConnCase, async: true

      test "filters by name", %{conn: conn} do
        params = %{filters: %{0 => %{field: "name", op: "==", value: "Staging"}}}
        conn |> get(~p"/api/v1/tenants/\#{tenant_id}/workspaces?\#{params}")
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/workspace_controller_test.exs")
    |> run_check(UseVerifiedRoutes)
    |> refute_issues()
  end

  test "does not report OpenAPI URI template strings" do
    """
    defmodule BylawWeb.Api.V1.WorkspaceOpenApiTest do
      use BylawWeb.ConnCase, async: true

      @collection_path "/api/v1/tenants/{tenant_id}/workspaces"
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/workspace_openapi_test.exs")
    |> run_check(UseVerifiedRoutes)
    |> refute_issues()
  end

  test "does not report non-web tests that do not use ConnCase" do
    """
    defmodule Bylaw.SomeLibraryTest do
      use ExUnit.Case, async: true

      test "keeps a path string" do
        path = "/api/v1/openapi"
        assert is_binary(path)
      end
    end
    """
    |> to_source_file("lib/bylaw/some_library_test.exs")
    |> run_check(UseVerifiedRoutes)
    |> refute_issues()
  end
end
