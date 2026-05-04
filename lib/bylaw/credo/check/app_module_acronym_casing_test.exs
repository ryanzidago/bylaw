defmodule Bylaw.Credo.Check.AppModuleAcronymCasingTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.AppModuleAcronymCasing

  test "flags app-owned module definitions with title-cased acronym words" do
    """
    defmodule BylawWeb.Api.V1.ToolController do
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> assert_issue(%{
      line_no: 1,
      trigger: "BylawWeb.Api.V1.ToolController",
      message: ~r/BylawWeb.API.V1.ToolController/
    })
  end

  test "flags app-owned aliases with title-cased acronym words" do
    """
    defmodule Bylaw.Example do
      alias Bylaw.Accounts.TenantApiKey
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> assert_issue(%{
      line_no: 2,
      trigger: "Bylaw.Accounts.TenantApiKey",
      message: ~r/Bylaw.Accounts.TenantAPIKey/
    })
  end

  test "flags relative api namespaces inside app-owned modules" do
    """
    defmodule BylawWeb.Router do
      def controller, do: Api.V1.OpenApiTest
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> assert_issue(%{
      line_no: 2,
      trigger: "Api.V1.OpenApiTest",
      message: ~r/API.V1.OpenAPITest/
    })
  end

  test "does not flag relative api namespaces outside app-owned modules" do
    """
    defmodule Example do
      def controller, do: Api.V1.OpenApiTest
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> refute_issues()
  end

  test "does not flag external modules" do
    """
    defmodule BylawWeb.Api.V1.ToolController do
      use OpenApiSpex.ControllerSpecs
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> assert_issue(%{
      line_no: 1,
      trigger: "BylawWeb.Api.V1.ToolController"
    })
  end

  test "does not flag mix task modules" do
    """
    defmodule Mix.Tasks.Qa do
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> refute_issues()
  end

  test "does not flag already-uppercased app modules" do
    """
    defmodule BylawWeb.API.V1.RunJSON do
      alias Bylaw.Integrations.LLM
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> refute_issues()
  end

  test "does not crash on aliases with dynamic module segments" do
    """
    defmodule Bylaw.Example do
      def adapter, do: __MODULE__.CaptureAdapter
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> refute_issues()
  end

  test "flags HTTP acronym words in app-owned modules" do
    """
    defmodule Bylaw.TestSupport.ExAwsHttpClient do
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> assert_issue(%{
      line_no: 1,
      trigger: "Bylaw.TestSupport.ExAwsHttpClient",
      message: ~r/Bylaw.TestSupport.ExAwsHTTPClient/
    })
  end

  test "flags UUID acronym words in app-owned modules" do
    """
    defmodule Bylaw.DatabaseCheck.UuidKeys do
    end
    """
    |> to_source_file()
    |> run_check(AppModuleAcronymCasing)
    |> assert_issue(%{
      line_no: 1,
      trigger: "Bylaw.DatabaseCheck.UuidKeys",
      message: ~r/Bylaw.DatabaseCheck.UUIDKeys/
    })
  end
end
