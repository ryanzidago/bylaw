defmodule Bylaw.Contract.ExUnitFormatter do
  @moduledoc """
  ExUnit formatter adapter for running Bylaw.Contract against an application.

  It inspects the current Mix project's application by default. Set
  `BYLAW_CONTRACT_APPS` to a comma-separated list of OTP application names when a
  suite exercises more than one application. Set `BYLAW_CONTRACT_REPORT=summary`
  for compact, machine-readable output.

  Select checks through the arbitrary ExUnit option passed to formatters:

      ExUnit.start(
        bylaw_contract: [
          checks: [
            Bylaw.Contract.Check.Typespec,
            Bylaw.Contract.Check.FunctionClauses,
            Bylaw.Contract.Check.ElixirCompiler
          ]
        ]
      )
  """

  use GenServer

  alias Bylaw.Contract.Tracer

  @impl GenServer
  def init(ex_unit_options) do
    with {:ok, modules} <- application_modules(),
         {:ok, options} <- observation_options(ex_unit_options),
         {:ok, tracer} <- Bylaw.Contract.start(modules, options) do
      {:ok, %{tracer: tracer, error: nil}}
    else
      {:error, reason} ->
        {:ok, %{tracer: nil, error: reason}}
    end
  end

  defp observation_options(ex_unit_options) do
    case Keyword.get(ex_unit_options, :bylaw_contract, []) do
      options when is_list(options) ->
        {:ok, options}

      options ->
        {:error, "expected :bylaw_contract to be a keyword list, got: #{inspect(options)}"}
    end
  end

  @impl GenServer
  def handle_cast({:suite_started, _}, %{tracer: tracer} = state) when is_pid(tracer) do
    Tracer.start_observation_window(tracer)
    {:noreply, state}
  end

  def handle_cast({:test_started, test}, %{tracer: tracer} = state) when is_pid(tracer) do
    Tracer.ex_unit_test_started(tracer, {test.case, test.name})
    {:noreply, state}
  end

  def handle_cast({:test_finished, test}, %{tracer: tracer} = state) when is_pid(tracer) do
    Tracer.ex_unit_test_finished(tracer, {test.case, test.name})
    {:noreply, state}
  end

  def handle_cast({:suite_finished, _}, %{tracer: tracer} = state) when is_pid(tracer) do
    coverage = Bylaw.Contract.stop(tracer)
    print_result(coverage)
    {:noreply, %{state | tracer: nil}}
  end

  def handle_cast({:suite_finished, _}, %{error: error} = state) do
    IO.puts("Bylaw.Contract QA error: #{error}")
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_, %{tracer: tracer}) when is_pid(tracer) do
    if Process.alive?(tracer) do
      Bylaw.Contract.stop(tracer)
    end

    :ok
  end

  def terminate(_, _), do: :ok

  defp application_modules do
    with {:ok, applications} <- applications() do
      result =
        Enum.reduce_while(applications, {:ok, []}, fn application, {:ok, modules} ->
          case Application.spec(application, :modules) do
            nil -> {:halt, {:error, "OTP application #{inspect(application)} is not loaded"}}
            application_modules -> {:cont, {:ok, application_modules ++ modules}}
          end
        end)

      case result do
        {:ok, modules} -> {:ok, Enum.uniq(modules)}
        error -> error
      end
    end
  end

  defp applications do
    names =
      case System.get_env("BYLAW_CONTRACT_APPS") do
        nil ->
          [Mix.Project.config()[:app]]

        value ->
          value
          |> String.split(",", trim: true)
          |> Enum.map(&String.trim/1)
      end

    Enum.reduce_while(names, {:ok, []}, fn
      nil, _ ->
        {:halt, {:error, "could not determine the current Mix application"}}

      name, {:ok, applications} when is_atom(name) ->
        {:cont, {:ok, [name | applications]}}

      name, {:ok, applications} ->
        try do
          {:cont, {:ok, [String.to_existing_atom(name) | applications]}}
        rescue
          ArgumentError -> {:halt, {:error, "unknown OTP application #{inspect(name)}"}}
        end
    end)
  end

  defp print_result(coverage) do
    if System.get_env("BYLAW_CONTRACT_REPORT") == "summary" do
      summary = Bylaw.Contract.summary(coverage)

      IO.puts(
        "Bylaw.Contract QA: " <>
          Enum.map_join(
            [
              :functions,
              :arguments,
              :calls,
              :input_classes,
              :supported_input_classes,
              :observed_input_classes,
              :missed_input_classes,
              :unsupported_input_classes,
              :boundaries,
              :observed_boundaries,
              :missed_boundaries,
              :return_groups,
              :return_events,
              :return_alternatives,
              :supported_return_alternatives,
              :observed_return_alternatives,
              :missed_return_alternatives,
              :unsupported_return_alternatives,
              :compiler_return_groups,
              :compiler_call_events,
              :compiler_return_alternatives,
              :supported_compiler_return_alternatives,
              :observed_compiler_return_alternatives,
              :missed_compiler_return_alternatives,
              :unsupported_compiler_return_alternatives,
              :compiler_modules,
              :compiler_unsupported,
              :compiler_warnings,
              :clauses,
              :clauses_selected,
              :clauses_head_matched,
              :guarded_clauses,
              :guards_passed,
              :guards_rejected,
              :callable_arities,
              :arity_calls,
              :structural_unsupported,
              :warnings
            ],
            " ",
            &"#{&1}=#{Map.fetch!(summary, &1)}"
          )
      )
    else
      Bylaw.Contract.print_report(coverage)
    end
  end
end
