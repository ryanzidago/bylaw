# Load with elixir -pa BYLAW_EBIN -r qa/candidate-capture.exs -S mix test
#   --formatter ExUnit.CLIFormatter --formatter Bylaw.Contract.QA.CandidateCapture
# Set BYLAW_CONTRACT_APPS, BYLAW_AUDIT_EBIN, and BYLAW_AUDIT_OUTPUT explicitly.
defmodule Bylaw.Contract.QA.CandidateCapture do
  use GenServer

  alias Bylaw.Contract.Check
  alias Bylaw.Contract.ExUnitFormatter

  @impl GenServer
  def init(options) do
    Code.prepend_path(System.fetch_env!("BYLAW_AUDIT_EBIN"))
    File.write!(System.fetch_env!("BYLAW_AUDIT_OUTPUT") <> ".lifecycle", "init\n")
    checks = [Check.Typespec, Check.FunctionClauses, Check.ElixirCompiler]
    options = Keyword.put(options, :bylaw_contract, checks: checks)
    {:ok, state} = ExUnitFormatter.init(options)

    File.write!(System.fetch_env!("BYLAW_AUDIT_OUTPUT") <> ".lifecycle", "initialized\n", [
      :append
    ])

    if is_pid(state.tracer) and System.get_env("BYLAW_AUDIT_COMPILER_PLAN") == "1" do
      plans =
        for worker <- :sys.get_state(state.tracer).workers,
            runtime = :sys.get_state(worker).runtime,
            runtime.module == Check.ElixirCompiler do
          Map.take(runtime.state, [:rules_by_mfa, :alternatives_by_mfa])
        end

      File.write!(
        System.fetch_env!("BYLAW_AUDIT_OUTPUT") <> ".compiler-plan",
        :erlang.term_to_binary(plans, [:compressed])
      )
    end

    {:ok,
     Map.merge(state, %{
       test_states: %{},
       failed_tests: [],
       audit_options: Keyword.take(options, [:seed, :exclude, :include, :max_cases])
     })}
  end

  @impl GenServer
  def handle_cast({:test_finished, test} = event, state) do
    status = if is_tuple(test.state), do: elem(test.state, 0), else: test.state || :passed
    state = update_in(state.test_states, &Map.update(&1, status, 1, fn count -> count + 1 end))

    state =
      if status == :failed,
        do: %{state | failed_tests: [{test.case, test.name} | state.failed_tests]},
        else: state

    ExUnitFormatter.handle_cast(event, state)
  end

  def handle_cast({:suite_finished, _}, %{tracer: tracer} = state) when is_pid(tracer) do
    File.write!(System.fetch_env!("BYLAW_AUDIT_OUTPUT") <> ".lifecycle", "finishing\n", [:append])
    coverage = Bylaw.Contract.stop(tracer)

    result = %{
      elixir: System.version(),
      otp: System.otp_release(),
      options: state.audit_options,
      test_states: state.test_states,
      failed_tests: Enum.reverse(state.failed_tests),
      coverage: coverage,
      summary: Bylaw.Contract.summary(coverage)
    }

    output = System.fetch_env!("BYLAW_AUDIT_OUTPUT")
    File.write!(output, :erlang.term_to_binary(result, [:compressed]))
    IO.puts("Bylaw candidate audit saved to #{output}")
    {:noreply, %{state | tracer: nil}}
  end

  def handle_cast(event, state), do: ExUnitFormatter.handle_cast(event, state)

  @impl GenServer
  def terminate(reason, state), do: ExUnitFormatter.terminate(reason, state)
end
