defmodule Bylaw.Test.SandboxUsage.Formatter do
  @moduledoc """
  ExUnit formatter that notifies `Bylaw.Test.SandboxUsage` when watched tests finish.
  """

  use GenServer

  alias Bylaw.Test.SandboxUsage

  @doc "Initializes the formatter with the configured `Bylaw.Test.SandboxUsage` server."
  @impl GenServer
  @spec init(ex_unit_options :: keyword()) :: {:ok, %{server: GenServer.server()}}
  def init(ex_unit_options) do
    server =
      ex_unit_options
      |> Keyword.get(:bylaw_test, [])
      |> Keyword.get(:server, SandboxUsage)

    {:ok, %{server: server}}
  end

  @doc false
  @impl GenServer
  @spec handle_cast(event :: term(), state :: %{server: GenServer.server()}) ::
          {:noreply, %{server: GenServer.server()}}
  def handle_cast(
        {:test_finished, %ExUnit.Test{state: nil, case: module, name: name}},
        %{server: server} = state
      ) do
    if SandboxUsage.running?(server) do
      SandboxUsage.record_test_finished(server, {module, name}, :passed)
    end

    {:noreply, state}
  end

  def handle_cast(
        {:test_finished, %ExUnit.Test{case: module, name: name}},
        %{server: server} = state
      ) do
    if SandboxUsage.running?(server) do
      SandboxUsage.record_test_finished(server, {module, name}, :not_passed)
    end

    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end
