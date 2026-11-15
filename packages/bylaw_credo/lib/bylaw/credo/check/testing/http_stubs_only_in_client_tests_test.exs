defmodule Bylaw.Credo.Check.Testing.HTTPStubsOnlyInClientTestsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Testing.HTTPStubsOnlyInClientTests

  @stubs """
  defmodule SampleTest do
    use ExUnit.Case

    test "pays" do
      Req.Test.stub(MyApp.Integrations.Payments.Api, fn conn ->
        Req.Test.json(conn, %{id: "pi_1"})
      end)
    end
  end
  """

  test "reports Req.Test in tests outside the clients' tests, with its line" do
    @stubs
    |> to_source_file("test/my_app/orders/payments_test.exs")
    |> run_check(HTTPStubsOnlyInClientTests)
    |> assert_issues(fn issues ->
      triggers =
        issues
        |> Enum.map(&{&1.line_no, &1.trigger})
        |> Enum.sort()

      assert triggers == [{5, "Req.Test.stub"}, {6, "Req.Test.json"}]
      assert Enum.all?(issues, &(&1.message =~ "behaviour mock"))
    end)
  end

  test "reports Req.Test in lib and test/support" do
    for path <- ["lib/my_app/integrations/payments/api.ex", "test/support/payments_helpers.ex"] do
      @stubs
      |> to_source_file(path)
      |> run_check(HTTPStubsOnlyInClientTests)
      |> assert_issues(2)
    end
  end

  test "resolves aliases and imports" do
    """
    defmodule SampleTest do
      alias Req.Test, as: Stubs
      import Req.Test

      def setup_stub, do: Stubs.expect(Api, fn conn -> conn end)
      def share(pid), do: Stubs.allow(Api, self(), pid)
    end
    """
    |> to_source_file("test/my_app_web/sample_test.exs")
    |> run_check(HTTPStubsOnlyInClientTests)
    |> assert_issues(fn issues ->
      triggers =
        issues
        |> Enum.map(& &1.trigger)
        |> Enum.sort()

      assert triggers == ["Req.Test.allow", "Req.Test.expect", "import Req.Test"]
    end)
  end

  test "allows Req.Test in the clients' own tests" do
    @stubs
    |> to_source_file("test/my_app/integrations/payments/api_test.exs")
    |> run_check(HTTPStubsOnlyInClientTests)
    |> refute_issues()
  end

  test "allows Req.Test mentioned as a plug in config" do
    """
    import Config

    config :my_app, MyApp.Integrations.Payments,
      req_options: [plug: {Req.Test, MyApp.Integrations.Payments.Api}, retry: false]
    """
    |> to_source_file("config/test.exs")
    |> run_check(HTTPStubsOnlyInClientTests)
    |> refute_issues()
  end

  test "honours custom allowed paths and stub modules" do
    source = """
    defmodule SampleTest do
      def a, do: Bypass.open()
      def b, do: Req.Test.stub(Api, fn conn -> conn end)
    end
    """

    params = [allowed_paths: ["test/clients/"], modules: [Bypass]]

    source
    |> to_source_file("test/my_app/integrations/sample_test.exs")
    |> run_check(HTTPStubsOnlyInClientTests, params)
    |> assert_issue(fn issue -> assert issue.trigger == "Bypass.open" end)

    source
    |> to_source_file("test/clients/sample_test.exs")
    |> run_check(HTTPStubsOnlyInClientTests, params)
    |> refute_issues()
  end
end
