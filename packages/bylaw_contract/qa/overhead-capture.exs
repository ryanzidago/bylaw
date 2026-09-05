# Load with -r and select this formatter alongside ExUnit.CLIFormatter.
# BYLAW_OVERHEAD_MODE: disabled, typespec, structural, compiler, or all.
# BYLAW_OVERHEAD_OUTPUT: unique ETF output path. Enabled modes also require
# BYLAW_OVERHEAD_EBIN, restored after Mix adjusts dependency code paths.
defmodule BylawOverheadCapture do
  use GenServer

  @impl GenServer
  def init(options) do
    started = System.monotonic_time(:microsecond)
    mode = System.fetch_env!("BYLAW_OVERHEAD_MODE")

    checks =
      case mode do
        "disabled" ->
          []

        "typespec" ->
          [Bylaw.Contract.Check.Typespec]

        "structural" ->
          [Bylaw.Contract.Check.FunctionClauses]

        "compiler" ->
          [Bylaw.Contract.Check.ElixirCompiler]

        "all" ->
          [
            Bylaw.Contract.Check.Typespec,
            Bylaw.Contract.Check.FunctionClauses,
            Bylaw.Contract.Check.ElixirCompiler
          ]
      end

    delegate =
      if mode == "disabled" do
        verify_disabled!()
        nil
      else
        Code.prepend_path(System.fetch_env!("BYLAW_OVERHEAD_EBIN"))

        {:ok, delegate} =
          apply(Bylaw.Contract.ExUnitFormatter, :init, [
            Keyword.put(options, :bylaw_contract, checks: checks)
          ])

        true = is_pid(delegate.tracer)
        delegate
      end

    {:ok,
     %{
       mode: mode,
       delegate: delegate,
       init_us: System.monotonic_time(:microsecond) - started,
       suite_started: nil,
       test_states: %{},
       failures: [],
       options: Keyword.take(options, [:seed, :max_cases, :include, :exclude])
     }}
  end

  @impl GenServer
  def handle_cast({:suite_started, _} = event, state) do
    {:noreply, delegate(event, %{state | suite_started: System.monotonic_time(:microsecond)})}
  end

  def handle_cast({:test_finished, test} = event, state) do
    status = if is_tuple(test.state), do: elem(test.state, 0), else: test.state || :passed
    state = update_in(state.test_states, &Map.update(&1, status, 1, fn count -> count + 1 end))

    state =
      if status in [:failed, :invalid],
        do: %{state | failures: [{test.module, test.name, test.state} | state.failures]},
        else: state

    {:noreply, delegate(event, state)}
  end

  def handle_cast({:suite_finished, timings}, state) do
    stopping = System.monotonic_time(:microsecond)

    coverage =
      if state.delegate do
        apply(Bylaw.Contract, :stop, [state.delegate.tracer])
      else
        verify_disabled!()
        nil
      end

    result = %{
      mode: state.mode,
      elixir: System.version(),
      otp: System.otp_release(),
      options: state.options,
      init_us: state.init_us,
      observed_suite_us: stopping - state.suite_started,
      stop_us: System.monotonic_time(:microsecond) - stopping,
      ex_unit_timings: timings,
      test_states: state.test_states,
      failures: Enum.reverse(state.failures),
      coverage: coverage
    }

    File.write!(System.fetch_env!("BYLAW_OVERHEAD_OUTPUT"), :erlang.term_to_binary(result))
    IO.puts("Overhead capture complete: #{state.mode}")
    {:noreply, %{state | delegate: nil}}
  end

  def handle_cast(event, state), do: {:noreply, delegate(event, state)}

  @impl GenServer
  def terminate(reason, %{delegate: delegate}) when not is_nil(delegate) do
    apply(Bylaw.Contract.ExUnitFormatter, :terminate, [reason, delegate])
  end

  def terminate(_, _), do: :ok

  defp delegate(_, %{delegate: nil} = state), do: state

  defp delegate(event, state) do
    {:noreply, delegate} =
      apply(Bylaw.Contract.ExUnitFormatter, :handle_cast, [event, state.delegate])

    %{state | delegate: delegate}
  end

  defp verify_disabled! do
    loaded =
      Enum.filter(:code.all_loaded(), fn {module, _} ->
        String.starts_with?(Atom.to_string(module), "Elixir.Bylaw.Contract")
      end)

    if Enum.any?(loaded), do: raise("Bylaw loaded during disabled control: #{inspect(loaded)}")
  end
end
