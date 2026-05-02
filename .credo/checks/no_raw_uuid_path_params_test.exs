defmodule Bylaw.Credo.Check.Warning.NoRawUUIDPathParamsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Warning.NoRawUUIDPathParams

  test "reports bracket access to a UUID path param from controller params" do
    """
    defmodule BylawWeb.API.V1.RunController do
      def show(conn, params) do
        params["id"]
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/run_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> assert_issue(%{line_no: 3, trigger: "id"})
  end

  test "reports conn.path_params bracket access in auth plugs" do
    """
    defmodule BylawWeb.Auth.RequireAPIKey do
      def call(conn, _opts) do
        conn.path_params["tenant_id"]
      end
    end
    """
    |> to_source_file("lib/bylaw_web/auth/require_api_key.ex")
    |> run_check(NoRawUUIDPathParams)
    |> assert_issue(%{line_no: 3, trigger: "tenant_id"})
  end

  test "reports conn.params bracket access to a UUID path param" do
    """
    defmodule BylawWeb.API.V1.RunController do
      def show(conn, _params) do
        conn.params["id"]
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/run_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> assert_issue(%{line_no: 3, trigger: "id"})
  end

  test "reports Map.get access to a UUID path param" do
    """
    defmodule BylawWeb.API.V1.RunController do
      def show(conn, params) do
        Map.get(params, "id")
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/run_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> assert_issue(%{line_no: 3, trigger: "id"})
  end

  test "reports Map.fetch access to a UUID path param from conn.params" do
    """
    defmodule BylawWeb.API.V1.WorkspaceController do
      def show(conn, _params) do
        Map.fetch(conn.params, "workspace_id")
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/workspace_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> assert_issue(%{line_no: 3, trigger: "workspace_id"})
  end

  test "reports Map.fetch! access to a UUID path param" do
    """
    defmodule BylawWeb.API.V1.WorkspaceController do
      def show(conn, _params) do
        Map.fetch!(conn.path_params, "workspace_id")
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/workspace_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> assert_issue(%{line_no: 3, trigger: "workspace_id"})
  end

  test "reports get_in access to a UUID path param" do
    """
    defmodule BylawWeb.API.V1.ConversationController do
      def show(conn, _params) do
        get_in(conn.path_params, ["conversation_id"])
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/conversation_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> assert_issue(%{line_no: 3, trigger: "conversation_id"})
  end

  test "does not report non-path request params" do
    """
    defmodule BylawWeb.API.V1.RunController do
      def submit_tool_results(conn, params) do
        params["tool_results"]
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/run_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> refute_issues()
  end

  test "does not report non-router id-like params" do
    """
    defmodule BylawWeb.API.V1.RunController do
      def submit_tool_results(conn, params) do
        params["workspace_user_id"]
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/run_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> refute_issues()
  end

  test "does not report ParamCasting usage" do
    """
    defmodule BylawWeb.API.V1.RunController do
      alias BylawWeb.API.ParamCasting

      def show(conn, _params) do
        ParamCasting.cast_uuidv7_params(conn.path_params, ~w(tenant_id workspace_id id))
      end
    end
    """
    |> to_source_file("lib/bylaw_web/controllers/api/v1/run_controller.ex")
    |> run_check(NoRawUUIDPathParams)
    |> refute_issues()
  end

  test "does not report non-boundary files" do
    """
    defmodule Bylaw.Runs do
      def fetch_run(params) do
        params["id"]
      end
    end
    """
    |> to_source_file("lib/bylaw/runs.ex")
    |> run_check(NoRawUUIDPathParams)
    |> refute_issues()
  end
end
