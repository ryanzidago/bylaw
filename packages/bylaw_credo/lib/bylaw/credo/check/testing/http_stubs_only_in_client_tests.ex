defmodule Bylaw.Credo.Check.Testing.HTTPStubsOnlyInClientTests do
  @moduledoc """
  Keep HTTP stubs such as `Req.Test` in the HTTP clients' own tests, so tests of code that uses a service expect on its behaviour mock instead.

  ## Examples

  Avoid:

        # test/my_app/orders_test.exs
        test "places an order" do
          Req.Test.stub(MyApp.Integrations.Payments.Api, fn conn ->
            Req.Test.json(conn, %{id: "ch_1"})
          end)

          assert {:ok, _order} = Orders.place(order)
        end

  Prefer:

        # test/my_app/orders_test.exs
        test "places an order" do
          expect(MyApp.Integrations.PaymentsMock, :charge, fn _params -> {:ok, %{id: "ch_1"}} end)

          assert {:ok, _order} = Orders.place(order)
        end

        # test/my_app/integrations/payments/api_test.exs
        test "charges through the payments API" do
          Req.Test.stub(MyApp.Integrations.Payments.Api, fn conn ->
            Req.Test.json(conn, %{id: "ch_1"})
          end)

          assert {:ok, %{id: "ch_1"}} = Api.charge(%{amount: 100})
        end


  Only the client's own tests should know what the service's requests and
  responses look like. When a test of business logic stubs HTTP, it breaks
  whenever the wire format changes and repeats knowledge the client already
  owns. Expecting on the integration's behaviour mock keeps those tests about
  the application's own decisions.

  Outside `:allowed_paths`, the check reports every call to, or `import` of,
  a module listed in `:modules` (by default `Req.Test`). It resolves aliases
  (`alias Req.Test, as: Stubs`) and allows the module mentioned as a value,
  such as `plug: {Req.Test, MyApp.Integrations.Payments.Api}` in
  `config/test.exs`.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.HTTPStubsOnlyInClientTests,
           [
             allowed_paths: ["test/my_app/integrations/"],
             modules: [Req.Test, Bypass]
           ]}
        ]
      }
    ]
  }
  ```

  - `:allowed_paths` - Path substrings or regexes where HTTP stubs are
    allowed. Defaults to `[~r"(^|/)test/(.*/)?integrations/"]`, any
    `integrations/` directory under `test/`.
  - `:modules` - Stub modules whose calls and imports are reported.
    Defaults to `[Req.Test]`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.HTTPStubsOnlyInClientTests, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    tags: [:testing],
    param_defaults: [
      allowed_paths: [~r"(^|/)test/(.*/)?integrations/"],
      modules: [Req.Test]
    ],
    explanations: [
      check: @moduledoc,
      params: [
        allowed_paths: "Path substrings or regexes where HTTP stubs are allowed.",
        modules: "Stub modules whose calls and imports are reported."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    allowed_paths = Params.get(params, :allowed_paths, __MODULE__)

    if RemoteCalls.matches_path?(source_file.filename, allowed_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      modules =
        params
        |> Params.get(:modules, __MODULE__)
        |> Enum.map(&RemoteCalls.module_name/1)

      source_file
      |> Credo.SourceFile.ast()
      |> RemoteCalls.calls()
      |> Enum.filter(fn call -> Enum.any?(modules, &RemoteCalls.within?(call.module, &1)) end)
      |> Enum.map(&issue_for(issue_meta, &1))
    end
  end

  defp issue_for(issue_meta, call) do
    format_issue(issue_meta,
      message:
        "Stub HTTP only in the HTTP clients' own tests; " <>
          "elsewhere, expect on the integration's behaviour mock.",
      trigger: RemoteCalls.trigger(call),
      line_no: call.line
    )
  end
end
