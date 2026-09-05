defmodule Bylaw.Contract.CheckSelectionAcceptanceTest do
  use ExUnit.Case, async: false

  alias Bylaw.Contract.Check
  alias Bylaw.Contract.Example.Registration
  alias Bylaw.Contract.TestFixtures.CompilerInferenceTarget

  defmodule ConfigurableCheck do
    @behaviour Bylaw.Contract.Check

    @impl Bylaw.Contract.Check
    def init(_modules, opts, _context) do
      send(Keyword.fetch!(opts, :notify), {:check_options, opts})

      {:ok, %{}, %{calls: MapSet.new(), returns: MapSet.new(), claims: MapSet.new()}}
    end

    @impl Bylaw.Contract.Check
    def observe(_event, state), do: state

    @impl Bylaw.Contract.Check
    def coverage(_state), do: %{}

    @impl Bylaw.Contract.Check
    def terminate(_state), do: :ok
  end

  defmodule ReturnOnlyCheck do
    @behaviour Bylaw.Contract.Check

    @impl Bylaw.Contract.Check
    def init(_modules, opts, _context) do
      mfa = Keyword.fetch!(opts, :mfa)
      state = %{notify: Keyword.fetch!(opts, :notify)}

      plan = %{calls: MapSet.new(), returns: MapSet.new([mfa]), claims: MapSet.new()}

      {:ok, state, plan}
    end

    @impl Bylaw.Contract.Check
    def observe(event, state) do
      send(state.notify, {:return_only_event, event})
      state
    end

    @impl Bylaw.Contract.Check
    def coverage(_state), do: %{}

    @impl Bylaw.Contract.Check
    def terminate(_state), do: :ok
  end

  test "the default check set enables typespec and structural checks" do
    {:ok, tracer} = Bylaw.Contract.start([Registration])
    coverage = Bylaw.Contract.stop(tracer)

    refute Enum.empty?(coverage.input_classes)
    refute Enum.empty?(coverage.clauses)
    assert Enum.empty?(coverage.compiler_return_alternatives)

    assert Map.keys(coverage.checks) |> Enum.sort() ==
             Enum.sort([Check.Typespec, Check.FunctionClauses])
  end

  test "an explicit check set can enable typespec checks without structural checks" do
    {:ok, tracer} = Bylaw.Contract.start([Registration], checks: [Check.Typespec])
    coverage = Bylaw.Contract.stop(tracer)

    refute Enum.empty?(coverage.input_classes)
    refute Enum.empty?(coverage.return_alternatives)
    assert Enum.empty?(coverage.clauses)
    assert Enum.empty?(coverage.structural_modules)
    assert Map.keys(coverage.checks) == [Check.Typespec]
  end

  test "an explicit check set can enable structural checks without typespec checks" do
    {:ok, tracer} = Bylaw.Contract.start([Registration], checks: [Check.FunctionClauses])
    coverage = Bylaw.Contract.stop(tracer)

    assert Enum.empty?(coverage.input_classes)
    assert Enum.empty?(coverage.return_alternatives)
    refute Enum.empty?(coverage.clauses)
    assert Map.keys(coverage.checks) == [Check.FunctionClauses]
  end

  test "the Elixir compiler check is opt-in and secondary to the typespec check" do
    {:ok, tracer} =
      Bylaw.Contract.start(
        [CompilerInferenceTarget, Registration],
        checks: [Check.Typespec, Check.ElixirCompiler]
      )

    assert CompilerInferenceTarget.outcome(true) == :accepted

    coverage = Bylaw.Contract.stop(tracer)

    assert Enum.any?(
             coverage.compiler_return_alternatives,
             &(&1.module == CompilerInferenceTarget)
           )

    refute Enum.any?(coverage.compiler_return_alternatives, &(&1.module == Registration))
    assert Enum.empty?(coverage.clauses)

    assert Map.keys(coverage.checks) |> Enum.sort() ==
             Enum.sort([Check.Typespec, Check.ElixirCompiler])
  end

  test "check specs accept options and reject duplicate check modules" do
    {:ok, tracer} =
      Bylaw.Contract.start(
        [Registration],
        checks: [{ConfigurableCheck, notify: self()}]
      )

    assert_receive {:check_options, [notify: notification_target]}
    assert notification_target == self()

    coverage = Bylaw.Contract.stop(tracer)
    assert coverage.checks[ConfigurableCheck] == %{}

    assert_raise ArgumentError, ~r/duplicate contract check/, fn ->
      Bylaw.Contract.start(
        [Registration],
        checks: [Check.Typespec, {Check.Typespec, []}]
      )
    end
  end

  test "an empty check set disables every contract check" do
    {:ok, tracer} = Bylaw.Contract.start([Registration], checks: [])
    coverage = Bylaw.Contract.stop(tracer)

    assert Enum.empty?(coverage.input_classes)
    assert Enum.empty?(coverage.return_alternatives)
    assert Enum.empty?(coverage.compiler_return_alternatives)
    assert Enum.empty?(coverage.clauses)
    assert coverage.checks == %{}
  end

  test "return-only checks receive returns without redundant call events" do
    mfa = {CompilerInferenceTarget, :outcome, 1}

    {:ok, tracer} =
      Bylaw.Contract.start(
        [CompilerInferenceTarget],
        checks: [{ReturnOnlyCheck, mfa: mfa, notify: self()}]
      )

    assert CompilerInferenceTarget.outcome(true) == :accepted
    Bylaw.Contract.stop(tracer)

    assert_receive {:return_only_event, {:return, ^mfa, :accepted}}
    refute_receive {:return_only_event, {:call, ^mfa, [true]}}
  end

  test "the ExUnit formatter prepares observation before the runner spawns tests" do
    {:ok, formatter} =
      Bylaw.Contract.ExUnitFormatter.init(bylaw_contract: [checks: [Check.FunctionClauses]])

    assert is_pid(formatter.tracer)
    coverage = Bylaw.Contract.stop(formatter.tracer)

    assert Enum.empty?(coverage.input_classes)
    refute Enum.empty?(coverage.clauses)
    assert Map.keys(coverage.checks) == [Check.FunctionClauses]
  end
end
