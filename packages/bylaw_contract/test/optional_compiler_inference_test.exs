defmodule Bylaw.Contract.OptionalCompilerInferenceTest do
  use ExUnit.Case

  alias Bylaw.Contract
  alias Bylaw.Contract.Check
  alias Bylaw.Contract.CompilerInference.Elixir120
  alias Bylaw.Contract.CompilerObserver
  alias Bylaw.Contract.TestFixtures.CompilerDeterministicTarget, as: Inferred
  alias Bylaw.Contract.TestFixtures.Registration

  @defaults [Check.Typespec, Check.FunctionClauses]

  test "the package accepts Elixir 1.19 without enabling compiler inference" do
    assert Version.match?("1.19.0", Mix.Project.config()[:elixir])
  end

  test "default checks observe specs and clauses without initializing compiler inference" do
    compiler_table = :ets.whereis(CompilerObserver)
    coverage = observe([Registration], [])

    assert MapSet.new(Map.keys(coverage.checks)) == MapSet.new(@defaults)
    assert :ets.whereis(CompilerObserver) == compiler_table

    assert Map.take(Contract.summary(coverage), [
             :calls,
             :return_events,
             :observed_return_alternatives,
             :clauses_selected,
             :compiler_modules
           ]) == %{
             calls: 3,
             return_events: 3,
             observed_return_alternatives: 2,
             clauses_selected: 2,
             compiler_modules: 0
           }
  end

  test "explicit compiler inference preserves supported results and reports unsupported runtimes" do
    original = Inferred.module_info(:md5)
    {:ok, observer} = Contract.start([Inferred], checks: [Check.ElixirCompiler])
    on_exit(fn -> stop_if_alive(observer) end)
    assert Inferred.outcome(:accept) == :accepted
    coverage = Contract.stop(observer)
    summary = Contract.summary(coverage)

    if Version.match?(System.version(), "~> 1.20") do
      assert summary.compiler_call_events == 1
      assert summary.observed_compiler_return_alternatives == 1
      assert summary.missed_compiler_return_alternatives == 1
      assert summary.compiler_unsupported == 0
      assert report(coverage) =~ "return: {:error, :rejected}"
    else
      assert [%{module: Inferred, status: :unsupported, reason: reason}] =
               coverage.compiler_modules

      assert reason =~ "unsupported Elixir checker version"
      assert summary.compiler_call_events == 0
      assert summary.missed_compiler_return_alternatives == 0
      assert Enum.empty?(coverage.compiler_return_alternatives)
      assert report(coverage) == ""

      assert {:error, "compiler inference requires Elixir 1.20 or newer"} =
               Elixir120.return_alternatives(Inferred, [])

      for module <- [Elixir120, Bylaw.Contract.CompilerClauseMapper] do
        assert {:ok, {^module, [imports: imports]}} =
                 :beam_lib.chunks(:code.which(module), [:imports])

        refute Enum.any?(imports, fn {dependency, _, _} ->
                 dependency == Module.Types.Descr
               end)
      end
    end

    assert Inferred.module_info(:md5) == original
    refute Map.has_key?(coverage, :incomplete)
  end

  test "compiler opt-in preserves default check results and restores observed module code" do
    modules = [Registration, Inferred]
    originals = Map.new(modules, &{&1, &1.module_info(:md5)})
    sessions = :trace.session_info(:all)
    defaults = observe(modules, [])
    combined = observe(modules, checks: @defaults ++ [Check.ElixirCompiler])

    for check <- @defaults, do: assert(combined.checks[check] == defaults.checks[check])
    assert Map.new(modules, &{&1, &1.module_info(:md5)}) == originals
    assert :trace.session_info(:all) == sessions
    refute Map.has_key?(combined, :incomplete)
  end

  defp observe(modules, options) do
    {:ok, observer} = Contract.start(modules, options)
    on_exit(fn -> stop_if_alive(observer) end)
    assert Registration.register(0) == {:error, :underage}
    assert Registration.register(17) == {:error, :underage}
    assert {:ok, %{id: 18}} = Registration.register(18)
    if Inferred in modules, do: assert(Inferred.outcome(:accept) == :accepted)
    Contract.stop(observer)
  end

  defp report(coverage) do
    {:ok, device} = StringIO.open("")
    :ok = Contract.print_report(coverage, device, colors: false)
    {_, output} = StringIO.contents(device)
    StringIO.close(device)
    output
  end

  defp stop_if_alive(observer) do
    if Process.alive?(observer), do: Contract.stop(observer)
  end
end
