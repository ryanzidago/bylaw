defmodule Bylaw.Contract.ExUnitFormatter do
  @moduledoc """
  ExUnit formatter that observes a test suite and prints the untested properties
  of the application's functions when the suite ends.

      # test/test_helper.exs
      ExUnit.start(formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter])

  By default it observes the modules of the current Mix application. Pass the
  modules explicitly to observe something else:

      ExUnit.start(
        formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter],
        bylaw_contract: [modules: [MyApp.Accounts]]
      )

  Functions that cannot be fully observed (recursive return values, modules
  without debug information) are summarised as a warning count. Pass
  `bylaw_contract: [warnings: true]` to print each warning.

  Pass `bylaw_contract: [since: "origin/main"]` (or set the `BYLAW_CONTRACT_SINCE`
  environment variable) to report only the functions that changed since a git
  revision, which turns the report into a review of a pull request.

  Pass `bylaw_contract: [baseline: "test/bylaw_contract_baseline.txt"]` to hide
  findings a team has reviewed and accepted (see `Bylaw.Contract.Baseline`). Run
  the suite with `BYLAW_CONTRACT_UPDATE_BASELINE=1` to rewrite that file.

  The formatter never changes the suite's result.
  """

  use GenServer

  alias Bylaw.Contract
  alias Bylaw.Contract.Baseline
  alias Bylaw.Contract.ChangedCode
  alias Bylaw.Contract.Report

  @doc false
  @impl GenServer
  def init(options) do
    config = Keyword.get(options, :bylaw_contract, [])
    modules = Keyword.get_lazy(config, :modules, &default_modules/0)

    case Contract.start(modules) do
      {:ok, session} ->
        {:ok,
         %{
           session: session,
           colors: Keyword.get(options, :colors, []),
           warnings?: Keyword.get(config, :warnings, false),
           baseline: Keyword.get(config, :baseline),
           since:
             Keyword.get_lazy(config, :since, fn -> System.get_env("BYLAW_CONTRACT_SINCE") end),
           not_run: 0,
           failed: 0
         }}

      {:error, :session_active} ->
        IO.puts("Bylaw.Contract: another observation is active; skipping")

        {:ok,
         %{
           session: nil,
           colors: [],
           warnings?: false,
           since: nil,
           baseline: nil,
           not_run: 0,
           failed: 0
         }}
    end
  end

  @doc false
  @impl GenServer
  def handle_cast({:suite_finished, _times}, %{session: session} = state) when session != nil do
    full = Contract.stop(session)
    update_baseline(full, state.baseline)
    {report, suppressed} = full |> restrict(state.since) |> apply_baseline(state.baseline)
    Report.print(report, :stdio, colors: colors?(state.colors))
    print_suppressed(suppressed)
    print_warnings(report, state.warnings?)
    print_test_run_note(state)
    {:noreply, %{state | session: nil}}
  end

  def handle_cast({:test_finished, %ExUnit.Test{state: {:excluded, _reason}}}, state),
    do: {:noreply, %{state | not_run: state.not_run + 1}}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:skipped, _reason}}}, state),
    do: {:noreply, %{state | not_run: state.not_run + 1}}

  def handle_cast({:test_finished, %ExUnit.Test{state: {:failed, _failures}}}, state),
    do: {:noreply, %{state | failed: state.failed + 1}}

  def handle_cast(_event, state), do: {:noreply, state}

  @doc false
  @impl GenServer
  def terminate(_reason, %{session: session}) when session != nil do
    Contract.stop(session)
    :ok
  end

  def terminate(_reason, _state), do: :ok

  @doc """
  Returns the modules of the current Mix application, excluding the observer's
  own runtime modules and modules compiled from the test directory.
  """
  @spec default_modules() :: list(module())
  def default_modules do
    case Mix.Project.config()[:app] do
      nil ->
        []

      app ->
        app |> Application.spec(:modules) |> List.wrap() |> Enum.reject(&excluded?/1)
    end
  end

  defp excluded?(module) do
    module in Contract.runtime_modules() or test_support?(module)
  end

  defp test_support?(module) do
    with {:module, ^module} <- Code.ensure_loaded(module),
         source when not is_nil(source) <- module.module_info(:compile)[:source] do
      source |> to_string() |> Path.relative_to_cwd() |> String.starts_with?("test/")
    else
      _unknown -> false
    end
  end

  defp update_baseline(report, path) when is_binary(path) do
    if System.get_env("BYLAW_CONTRACT_UPDATE_BASELINE") in [nil, "", "0"] do
      :ok
    else
      Baseline.write(report, path)
      IO.puts("Bylaw.Contract: wrote #{Enum.count(Report.missed(report))} findings to #{path}")
    end
  end

  defp update_baseline(_report, _path), do: :ok

  defp apply_baseline(report, path) when is_binary(path), do: Baseline.apply(report, path)
  defp apply_baseline(report, _path), do: {report, 0}

  defp print_suppressed(0), do: :ok

  defp print_suppressed(count),
    do: IO.puts("Bylaw.Contract: #{count} findings hidden by the baseline")

  defp restrict(report, nil), do: report
  defp restrict(report, since), do: ChangedCode.filter(report, since: since)

  defp colors?(options) when is_list(options),
    do: Keyword.get(options, :enabled, IO.ANSI.enabled?())

  defp colors?(_options), do: IO.ANSI.enabled?()

  defp print_test_run_note(%{not_run: 0, failed: 0}), do: :ok

  defp print_test_run_note(%{not_run: not_run, failed: failed}) do
    IO.puts(
      "Bylaw.Contract: findings reflect only the tests that ran: " <>
        "#{not_run} excluded or skipped, #{failed} failed"
    )
  end

  defp print_warnings(%Report{warnings: []}, _all?), do: :ok

  defp print_warnings(%Report{warnings: warnings}, true),
    do: Enum.each(warnings, &IO.puts("Bylaw.Contract warning: #{&1}"))

  defp print_warnings(%Report{warnings: warnings}, false) do
    count = Enum.count(warnings)

    noun =
      if count == 1 do
        "warning"
      else
        "warnings"
      end

    IO.puts(
      "Bylaw.Contract: #{count} #{noun} about functions that could not be fully observed " <>
        "(set bylaw_contract: [warnings: true] to print them)"
    )
  end
end
