defmodule Bylaw.Credo.Check.Elixir.NetworkOnlyInIntegrationsTest do
  use Credo.Test.Case

  alias Bylaw.Credo.Check.Elixir.NetworkOnlyInIntegrations

  test "reports Req calls outside the integrations, with their line" do
    """
    defmodule Sample do
      def fetch(url) do
        req = Req.new(base_url: url)
        Req.get!(req, url: "/menu")
      end

      def send_it(req), do: Req.request(req)
      def build, do: Req.Request.new(url: "https://example.com")
    end
    """
    |> to_source_file("lib/my_app/core/sample.ex")
    |> run_check(NetworkOnlyInIntegrations)
    |> assert_issues(fn issues ->
      triggers =
        issues
        |> Enum.map(&{&1.line_no, &1.trigger})
        |> Enum.sort()

      assert triggers == [
               {3, "Req.new"},
               {4, "Req.get!"},
               {7, "Req.request"},
               {8, "Req.Request.new"}
             ]

      assert Enum.all?(issues, &(&1.message =~ "/integrations/"))
    end)
  end

  test "resolves aliases, as: aliases and grouped aliases" do
    """
    defmodule Sample do
      alias Req, as: R
      alias Mint.{HTTP1, HTTP2}
      alias Swoosh.Mailer

      def a(url), do: R.get(url)
      def b, do: HTTP1.connect(:https, "example.com", 443)
      def c, do: HTTP2.connect(:https, "example.com", 443)
      def d(email), do: Mailer.deliver(email, [])
    end
    """
    |> to_source_file("lib/my_app_web/sample.ex")
    |> run_check(NetworkOnlyInIntegrations)
    |> assert_issues(fn issues ->
      triggers =
        issues
        |> Enum.map(& &1.trigger)
        |> Enum.sort()

      assert triggers == [
               "Mint.HTTP1.connect",
               "Mint.HTTP2.connect",
               "Req.get",
               "Swoosh.Mailer.deliver"
             ]
    end)
  end

  test "reports the other HTTP libraries, sockets, email delivery and imports" do
    """
    defmodule Sample do
      import Tesla

      def calls(email) do
        Finch.request(:req, MyFinch)
        HTTPoison.get("https://example.com")
        :httpc.request(~c"https://example.com")
        :hackney.request(:get, "https://example.com")
        :gen_tcp.connect(~c"example.com", 80, [])
        :ssl.connect(~c"example.com", 443, [])
        Swoosh.Mailer.deliver_many([email], [])
        Swoosh.Adapters.Resend.deliver(email, [])
        &Req.post/2
      end
    end
    """
    |> to_source_file("config/runtime.exs")
    |> run_check(NetworkOnlyInIntegrations)
    |> assert_issues(10)
  end

  test "allows calls inside the integrations and their tests" do
    source = """
    defmodule MyApp.Integrations.Payments.Api do
      def get(url), do: Req.get(url)
      def deliver(email), do: Swoosh.Mailer.deliver(email, [])
    end
    """

    for path <- [
          "lib/my_app/integrations/payments/api.ex",
          "test/my_app/integrations/payments/api_test.exs"
        ] do
      source
      |> to_source_file(path)
      |> run_check(NetworkOnlyInIntegrations)
      |> refute_issues()
    end
  end

  test "allows module names that are only mentioned, and Req.Test" do
    """
    import Config

    config :my_app, MyApp.Mailer, adapter: Swoosh.Adapters.Local
    config :swoosh, :api_client, Swoosh.ApiClient.Req
    config :my_app, MyApp.Integrations.Payments, req_options: [plug: {Req.Test, Api}]

    defmodule MyApp.Mailer do
      use Swoosh.Mailer, otp_app: :my_app
    end

    defmodule Sample do
      def start, do: Application.ensure_all_started(:ssl)
      def local?, do: Application.get_env(:my_app, MyApp.Mailer)[:adapter] == Swoosh.Adapters.Local
      def info, do: :ssl.versions()
      def deliver(email), do: MyApp.Integrations.Email.client().deliver(email)
      def stub, do: Req.Test.stub(Api, fn conn -> conn end)
    end
    """
    |> to_source_file("lib/my_app/sample.ex")
    |> run_check(NetworkOnlyInIntegrations)
    |> refute_issues()
  end

  test "reports an application mailer listed in functions, and honours custom paths and modules" do
    source = """
    defmodule Sample do
      import MyApp.Mailer

      def notify(email), do: MyApp.Mailer.deliver(email)
      def render(email), do: MyApp.Mailer.render(email)
      def fetch(url), do: MyHttp.get(url)
      def stub(url), do: Req.get(url)
    end
    """

    params = [
      allowed_paths: [~r"^lib/my_app/clients/"],
      modules: [MyHttp],
      functions: [{MyApp.Mailer, [:deliver]}]
    ]

    source
    |> to_source_file("lib/my_app/integrations/sample.ex")
    |> run_check(NetworkOnlyInIntegrations, params)
    |> assert_issues(fn issues ->
      triggers =
        issues
        |> Enum.map(& &1.trigger)
        |> Enum.sort()

      assert triggers == ["MyApp.Mailer.deliver", "MyHttp.get", "import MyApp.Mailer"]
    end)

    source
    |> to_source_file("lib/my_app/clients/sample.ex")
    |> run_check(NetworkOnlyInIntegrations, params)
    |> refute_issues()
  end
end
