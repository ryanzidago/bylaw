defmodule Bylaw.Credo.Check.Elixir.NetworkOnlyInIntegrations do
  @moduledoc """
  Keep every call to the network inside the integration layer, so the rest of the code calls an integration's behaviour instead of an HTTP, socket or email library.

  ## Examples

  Avoid:

        defmodule MyApp.Orders do
          def place(order) do
            Req.post!("https://api.payments.example/charges", json: charge(order))
          end
        end

  Prefer:

        defmodule MyApp.Integrations.Payments.Api do
          @behaviour MyApp.Integrations.Payments

          @impl MyApp.Integrations.Payments
          def charge(params), do: Req.post("https://api.payments.example/charges", json: params)
        end

        defmodule MyApp.Orders do
          def place(order), do: MyApp.Integrations.Payments.client().charge(charge(order))
        end


  When only the integration modules talk to the network, every outside
  service has one behaviour that names what the application needs from it.
  Tests of the rest of the code replace that behaviour with a mock (for
  example Mox or Hammox) and never depend on the wire format, retries or
  credentials, and swapping a provider touches one module.

  Outside `:allowed_paths`, the check reports a call to, or an `import` of:

  - any module listed in `:modules`, or one of its submodules (by default
    `Req`, `Finch`, `Mint.HTTP`, `Mint.HTTP1`, `Mint.HTTP2`, `HTTPoison`,
    `Tesla`, `:httpc`, `:hackney` and `Swoosh.Adapters`), except modules
    listed in `:allowed_modules` (by default `Req.Test`);
  - a function listed in `:functions` (by default `deliver`, `deliver!` and
    `deliver_many` on `Swoosh.Mailer`, and `connect` on `:gen_tcp` and
    `:ssl`).

  It resolves aliases, so `alias Req, as: R` followed by `R.get(url)` is
  reported. Module names that are only mentioned, such as
  `adapter: Swoosh.Adapters.Local` in config, `use Swoosh.Mailer` or
  `Application.ensure_all_started(:ssl)`, are allowed.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NetworkOnlyInIntegrations,
           [
             allowed_paths: ["lib/my_app/integrations/", "test/my_app/integrations/"],
             functions: [
               {MyApp.Mailer, [:deliver, :deliver!, :deliver_many]},
               {Swoosh.Mailer, [:deliver, :deliver!, :deliver_many]},
               {:gen_tcp, [:connect]},
               {:ssl, [:connect]}
             ]
           ]}
        ]
      }
    ]
  }
  ```

  - `:allowed_paths` - Path substrings or regexes where network calls are
    allowed. Defaults to `["/integrations/"]`.
  - `:modules` - Modules whose every function, and every submodule's
    function, counts as a network call. Defaults to the HTTP and email
    adapter libraries listed above.
  - `:allowed_modules` - Modules, and their submodules, that are never
    reported even when they sit under `:modules`. Defaults to `[Req.Test]`.
  - `:functions` - `{module, functions}` pairs for modules where only some
    functions reach the network, such as an application's Swoosh mailer.
    Calling a listed function or importing the module is reported.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NetworkOnlyInIntegrations, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [
      allowed_paths: ["/integrations/"],
      modules: [
        Req,
        Finch,
        Mint.HTTP,
        Mint.HTTP1,
        Mint.HTTP2,
        HTTPoison,
        Tesla,
        :httpc,
        :hackney,
        Swoosh.Adapters
      ],
      allowed_modules: [Req.Test],
      functions: [
        {Swoosh.Mailer, [:deliver, :deliver!, :deliver_many]},
        {:gen_tcp, [:connect]},
        {:ssl, [:connect]}
      ]
    ],
    explanations: [
      check: @moduledoc,
      params: [
        allowed_paths: "Path substrings or regexes where network calls are allowed.",
        modules:
          "Modules whose every function, and every submodule's function, calls the network.",
        allowed_modules: "Modules, and their submodules, that are never reported.",
        functions:
          "`{module, functions}` pairs for modules where only some functions call the network."
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
      rules = rules(params)

      source_file
      |> Credo.SourceFile.ast()
      |> RemoteCalls.calls()
      |> Enum.filter(&network?(&1, rules))
      |> Enum.map(&issue_for(issue_meta, &1, allowed_paths))
    end
  end

  defp rules(params) do
    functions =
      params
      |> Params.get(:functions, __MODULE__)
      |> Map.new(fn {module, functions} -> {RemoteCalls.module_name(module), functions} end)

    %{
      modules: module_names(params, :modules),
      allowed_modules: module_names(params, :allowed_modules),
      functions: functions
    }
  end

  defp module_names(params, key) do
    params
    |> Params.get(key, __MODULE__)
    |> Enum.map(&RemoteCalls.module_name/1)
  end

  defp network?(%{module: module, function: function}, rules) do
    cond do
      Enum.any?(rules.allowed_modules, &RemoteCalls.within?(module, &1)) -> false
      Enum.any?(rules.modules, &RemoteCalls.within?(module, &1)) -> true
      Map.has_key?(rules.functions, module) -> function in [:import | rules.functions[module]]
      true -> false
    end
  end

  defp issue_for(issue_meta, call, allowed_paths) do
    format_issue(issue_meta,
      message:
        "Call the network only from the integration layer (#{describe_paths(allowed_paths)}); " <>
          "elsewhere, call the integration's behaviour.",
      trigger: RemoteCalls.trigger(call),
      line_no: call.line
    )
  end

  defp describe_paths(paths) do
    Enum.map_join(paths, ", ", fn
      %Regex{} = regex -> "~r/#{Regex.source(regex)}/"
      path -> path
    end)
  end
end
