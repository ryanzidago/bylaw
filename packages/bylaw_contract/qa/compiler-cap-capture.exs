# Diagnostic formatter; see compiler-cap-2026-09-05.md for scope and invocation.
defmodule CompilerCapCapture do
  use GenServer
  alias Bylaw.Contract.Check.ElixirCompiler

  def init(_) do
    Code.prepend_path(System.fetch_env!("BYLAW_CAP_EBIN"))
    app = System.fetch_env!("BYLAW_CAP_APP") |> String.to_existing_atom()
    cap = System.fetch_env!("BYLAW_CAP") |> String.to_integer()
    started = System.monotonic_time(:microsecond)
    memory_before = :erlang.memory(:total)

    {:ok, check, plan} =
      ElixirCompiler.init(Application.spec(app, :modules), [max_functions: cap], %{
        claims: MapSet.new()
      })

    initialized = System.monotonic_time(:microsecond)
    memory_after = :erlang.memory(:total)

    eligible =
      check.compiler_return_alternatives
      |> Enum.filter(
        &(&1.inferable? and
            MapSet.member?(
              plan.claims,
              {:return_alternatives, {&1.module, &1.function, &1.arity}}
            ))
      )
      |> Enum.map(&{&1.module, &1.function, &1.arity})
      |> Enum.uniq()
      |> Enum.sort()

    session = :trace.session_create(:bylaw_cap_volume, self(), [])
    configured = Map.new(eligible, &{&1, :trace.function(session, &1, true, [:call_count])})

    {:ok,
     %{
       check: check,
       session: session,
       configured: configured,
       eligible: eligible,
       cap: cap,
       app: app,
       init_us: initialized - started,
       memory_before: memory_before,
       memory_after: memory_after,
       started: System.monotonic_time(:microsecond),
       tests: %{},
       failures: []
     }}
  end

  def handle_cast({:test_finished, test}, state) do
    status = if is_tuple(test.state), do: elem(test.state, 0), else: test.state || :passed

    failures =
      if status in [:failed, :invalid],
        do: [{test.module, test.name, test.state} | state.failures],
        else: state.failures

    {:noreply,
     %{state | tests: Map.update(state.tests, status, 1, &(&1 + 1)), failures: failures}}
  end

  def handle_cast({:suite_finished, _}, state) do
    :trace.function(state.session, {:_, :_, :_}, :pause, [:call_count])

    counts =
      Map.new(state.configured, fn {mfa, configured} ->
        if configured > 0 do
          {:call_count, count} = :trace.info(state.session, mfa, :call_count)
          {mfa, count}
        else
          {mfa, :unavailable}
        end
      end)

    coverage = ElixirCompiler.coverage(state.check)

    result = %{
      app: state.app,
      cap: state.cap,
      eligible: state.eligible,
      selected: Map.keys(state.check.alternatives_by_mfa),
      initially_unknown: state.check.unknown,
      selected_ids:
        state.check.alternatives_by_mfa |> Map.values() |> List.flatten() |> Enum.map(& &1.id),
      counts: counts,
      coverage: coverage,
      tests: state.tests,
      failures: state.failures,
      init_us: state.init_us,
      suite_us: System.monotonic_time(:microsecond) - state.started,
      memory_before: state.memory_before,
      memory_after: state.memory_after,
      memory_end: :erlang.memory(:total)
    }

    :trace.session_destroy(state.session)
    ElixirCompiler.terminate(state.check)
    File.write!(System.fetch_env!("BYLAW_CAP_OUTPUT"), :erlang.term_to_binary(result))
    IO.puts("Compiler cap capture complete")
    {:noreply, %{state | check: nil, session: nil}}
  end

  def handle_cast(_, state), do: {:noreply, state}
  def terminate(_, %{check: nil}), do: :ok

  def terminate(_, state) do
    :trace.session_destroy(state.session)
    ElixirCompiler.terminate(state.check)
  end
end
