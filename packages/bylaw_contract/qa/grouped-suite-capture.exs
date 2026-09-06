# Native ExUnit event capture; this does not install a contract observer.
defmodule BylawGroupedSuiteCapture do
  use GenServer

  @impl GenServer
  def init(options) do
    {:ok,
     %{
       options: Map.new(Keyword.take(options, [:seed, :max_cases])),
       tests: [],
       cases: [],
       active: %{},
       originals: original_modules()
     }}
  end

  @impl GenServer
  def handle_cast({:module_started, module}, state) do
    config = module.name.__ex_unit__(:config)

    row = %{
      module: Atom.to_string(module.name),
      group: inspect(config.group),
      async: config.async?,
      started_us: System.monotonic_time(:microsecond)
    }

    {:noreply, put_in(state.active[module.name], row)}
  end

  def handle_cast({:module_finished, module}, state) do
    {row, active} = Map.pop!(state.active, module.name)
    row = Map.put(row, :finished_us, System.monotonic_time(:microsecond))
    {:noreply, %{state | active: active, cases: [row | state.cases]}}
  end

  def handle_cast({:test_finished, test}, state) do
    status = if is_tuple(test.state), do: elem(test.state, 0), else: test.state || :passed

    row = %{
      module: Atom.to_string(test.module),
      name: Atom.to_string(test.name),
      file: test.tags.file,
      line: test.tags.line,
      state: Atom.to_string(status),
      failure: if(status in [:failed, :invalid], do: inspect(test.state, limit: :infinity)),
      time_us: test.time
    }

    {:noreply, %{state | tests: [row | state.tests]}}
  end

  def handle_cast({:suite_finished, timings}, state) do
    result = %{
      schema: 1,
      options: state.options,
      tests: Enum.reverse(state.tests),
      cases: Enum.reverse(state.cases),
      active_cases: Map.keys(state.active) |> Enum.map(&Atom.to_string/1),
      ex_unit_timings: timings,
      changed_modules: changed_modules(state.originals)
    }

    File.write!(System.fetch_env!("BYLAW_GROUPED_OUTPUT"), JSON.encode!(result) <> "\n")
    {:noreply, state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  @doc false
  @spec global_settings() :: map()
  def global_settings do
    %{
      cwd: File.cwd!(),
      compiler: Code.compiler_options(),
      ansi: Application.fetch_env(:elixir, :ansi_enabled),
      environment:
        Map.new(
          ~w(BYLAW_CONTRACT_APPS BYLAW_CONTRACT_REPORT BYLAW_CONTRACT_DIFF_BASE GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE),
          fn key ->
            {key, System.get_env(key)}
          end
        )
    }
  end

  @doc false
  @spec cleanup(map()) :: map()
  def cleanup(before) do
    after_settings = global_settings()

    workers =
      Enum.filter(Process.list(), fn pid ->
        case Process.info(pid, :dictionary) do
          {:dictionary, dictionary} ->
            case Keyword.get(dictionary, :"$initial_call") do
              {module, _, _} -> module in [Bylaw.Contract.Tracer, Bylaw.Contract.TraceWorker]
              _ -> false
            end

          nil ->
            false
        end
      end)

    shadows =
      for {module, _} <- :code.all_loaded(),
          String.starts_with?(
            Atom.to_string(module),
            "Elixir.Bylaw.Contract.StructuralCoverage.Shadow"
          ),
          do: Atom.to_string(module)

    sessions = :trace.session_info(:all) -- [{:legacy, :default}]

    checks = %{
      cwd_restored: before.cwd == after_settings.cwd,
      compiler_options_restored: before.compiler == after_settings.compiler,
      ansi_restored: before.ansi == after_settings.ansi,
      environment_restored: before.environment == after_settings.environment,
      workers: Enum.map(workers, &inspect/1),
      shadows: shadows,
      sessions: Enum.map(sessions, &inspect/1)
    }

    clean =
      checks.cwd_restored and checks.compiler_options_restored and checks.ansi_restored and
        checks.environment_restored and Enum.empty?(workers) and Enum.empty?(shadows) and
        Enum.empty?(sessions)

    Map.put(checks, :clean, clean)
  end

  defp original_modules do
    for module <- Application.spec(:bylaw_contract, :modules) || [],
        {^module, binary, _} <- [:code.get_object_code(module)],
        {:ok, {^module, md5}} <- [:beam_lib.md5(binary)],
        into: %{},
        do: {module, md5}
  end

  defp changed_modules(originals) do
    for {module, expected} <- originals,
        Code.loaded?(module),
        module.module_info(:md5) != expected,
        do: Atom.to_string(module)
  end
end

before = BylawGroupedSuiteCapture.global_settings()

System.at_exit(fn status ->
  output = System.fetch_env!("BYLAW_GROUPED_OUTPUT")
  cleanup = BylawGroupedSuiteCapture.cleanup(before)

  result =
    if File.exists?(output),
      do: output |> File.read!() |> JSON.decode!(),
      else: %{"schema" => 1, "missing_suite_capture" => true}

  clean =
    cleanup.clean and not Map.get(result, "missing_suite_capture", false) and
      Enum.empty?(Map.get(result, "active_cases", [])) and
      Enum.empty?(Map.get(result, "changed_modules", []))

  result =
    result
    |> Map.put("cleanup", Map.put(cleanup, :clean, clean))
    |> Map.put("process_status", status)

  File.write!(output, JSON.encode!(result) <> "\n")
  if status == 0 and not clean, do: exit({:shutdown, 2})
end)
