defmodule Bylaw.Contract.StructuralCoverageTest do
  use ExUnit.Case

  test "classifies authored clauses, complete guards, ordering, and private calls" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])

    assert Bylaw.Contract.StructuralExample.classify(:exact) == :exact
    assert Bylaw.Contract.StructuralExample.classify(:other_atom) == :atom
    assert Bylaw.Contract.StructuralExample.classify(7) == :positive_integer
    assert Bylaw.Contract.StructuralExample.classify(-1) == :integer
    assert Bylaw.Contract.StructuralExample.classify({:other}) == :other
    assert Bylaw.Contract.StructuralExample.through_private(:private_exact) == :private_exact
    assert Bylaw.Contract.StructuralExample.through_private(12) == :private_integer
    assert_raise FunctionClauseError, fn -> Bylaw.Contract.StructuralExample.guarded_only(-1) end

    coverage = Bylaw.Contract.stop(tracer)
    classify = clauses_for(coverage, :classify, 1)

    assert Enum.map(classify, & &1.line) == [5, 6, 7, 8, 9]
    assert length(Enum.uniq_by(classify, & &1.id)) == 5

    assert Enum.map(classify, & &1.source) == [
             "def classify(:exact)",
             "def classify(value) when is_atom(value)",
             "def classify(value) when is_integer(value) and value > 0",
             "def classify(value) when is_integer(value)",
             "def classify(_)"
           ]

    assert Enum.all?(
             classify,
             &String.ends_with?(&1.file, "lib/bylaw/contract/structural_example.ex")
           )

    assert outcome(coverage, Enum.at(classify, 0)) == %{
             selected: 1,
             head_matches: 1,
             guard_passes: 1,
             guard_rejections: 0
           }

    assert outcome(coverage, Enum.at(classify, 1)) == %{
             selected: 1,
             head_matches: 5,
             guard_passes: 2,
             guard_rejections: 3
           }

    assert outcome(coverage, Enum.at(classify, 2)) == %{
             selected: 1,
             head_matches: 5,
             guard_passes: 1,
             guard_rejections: 4
           }

    assert outcome(coverage, Enum.at(classify, 3)) == %{
             selected: 1,
             head_matches: 5,
             guard_passes: 2,
             guard_rejections: 3
           }

    assert outcome(coverage, Enum.at(classify, 4)).selected == 1

    private_clauses = clauses_for(coverage, :private_classify, 1)
    assert Enum.all?(private_clauses, &(&1.visibility == :private))
    assert Enum.map(private_clauses, &outcome(coverage, &1).selected) == [1, 1]

    [guarded_only] = clauses_for(coverage, :guarded_only, 1)
    assert outcome(coverage, guarded_only).head_matches == 1
    assert outcome(coverage, guarded_only).guard_rejections == 1
    assert outcome(coverage, guarded_only).selected == 0

    assert coverage.unmatched_clause_calls[
             {Bylaw.Contract.StructuralExample, :guarded_only, 1}
           ] == 1
  end

  test "reports default wrappers as arities without adding generated clauses" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])

    assert Bylaw.Contract.StructuralExample.optional(:left) == {:left, :default}
    assert Bylaw.Contract.StructuralExample.optional(:right, :explicit) == {:right, :explicit}

    assert Bylaw.Contract.StructuralExample.through_private_default(:value) ==
             {:value, :middle, :tail}

    coverage = Bylaw.Contract.stop(tracer)

    assert Enum.map(clauses_for(coverage, :optional, 2), & &1.position) == [1, 2]
    assert Enum.empty?(clauses_for(coverage, :optional, 1))

    optional_arities =
      coverage.arities
      |> Enum.filter(&(&1.function == :optional))
      |> Enum.map(&{&1.arity, &1.authored?, &1.default_wrapper?})

    assert optional_arities == [{1, false, true}, {2, true, false}]
    assert coverage.arity_calls[{Bylaw.Contract.StructuralExample, :optional, 1}] == 1
    assert coverage.arity_calls[{Bylaw.Contract.StructuralExample, :optional, 2}] == 2

    assert Enum.empty?(clauses_for(coverage, :private_default, 1))
    assert Enum.empty?(clauses_for(coverage, :private_default, 2))
    assert [%{visibility: :private}] = clauses_for(coverage, :private_default, 3)

    assert Enum.any?(
             coverage.arities,
             &(&1.function == :private_default and &1.arity == 1 and &1.default_wrapper?)
           )
  end

  test "shadow classification never executes original clause bodies" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])

    assert Bylaw.Contract.StructuralExample.body_probe(self(), :once) == :once
    assert_receive {:body_ran, :once}
    refute_receive {:body_ran, :once}, 20

    coverage = Bylaw.Contract.stop(tracer)
    [clause] = clauses_for(coverage, :body_probe, 2)
    assert outcome(coverage, clause).selected == 1
  end

  test "marks modules without usable debug information unsupported" do
    module = Module.concat(Bylaw.Contract, "NoDebugFixture")

    directory =
      Path.join(
        System.tmp_dir!(),
        "bylaw_contract-no-debug-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)

    compiler_options = Code.compiler_options()

    binary =
      try do
        Code.compiler_options(debug_info: false)

        [{^module, binary}] =
          Code.compile_string(
            "defmodule Bylaw.Contract.NoDebugFixture do\n  def ping, do: :pong\nend"
          )

        binary
      after
        Code.compiler_options(compiler_options)
      end

    :code.delete(module)
    :code.purge(module)
    beam_path = Path.join(directory, "Elixir.Bylaw.Contract.NoDebugFixture.beam")
    File.write!(beam_path, binary)
    true = :code.add_patha(String.to_charlist(directory))
    {:module, ^module} = :code.load_abs(String.to_charlist(Path.rootname(beam_path)))

    on_exit(fn ->
      :code.delete(module)
      :code.purge(module)
      :code.del_path(String.to_charlist(directory))
      File.rm_rf!(directory)
    end)

    {:ok, tracer} = Bylaw.Contract.start([module])
    assert module.ping() == :pong
    coverage = Bylaw.Contract.stop(tracer)

    assert Enum.empty?(coverage.clauses)

    assert [%{module: Bylaw.Contract.NoDebugFixture, status: :unsupported, reason: reason}] =
             coverage.structural_modules

    assert reason =~ "debug information"

    assert Bylaw.Contract.summary(coverage).structural_unsupported == 1
  end

  test "temporary classifiers remain isolated across concurrent trace sessions" do
    {:ok, first} = Bylaw.Contract.start([Bylaw.Contract.Example])
    {:ok, second} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])

    assert Bylaw.Contract.Example.greeting(:admin, :short) == "Welcome, admin"
    assert Bylaw.Contract.StructuralExample.classify(:exact) == :exact

    second_coverage = Bylaw.Contract.stop(second)

    assert Bylaw.Contract.Example.greeting(:member, :short) == "Welcome back"
    first_coverage = Bylaw.Contract.stop(first)

    assert first_coverage.arity_calls[{Bylaw.Contract.Example, :greeting, 2}] == 2

    assert second_coverage.arity_calls[{Bylaw.Contract.StructuralExample, :classify, 1}] == 1
  end

  defp clauses_for(coverage, function, arity) do
    Enum.filter(coverage.clauses, &(&1.function == function and &1.arity == arity))
  end

  defp outcome(coverage, clause), do: Map.fetch!(coverage.clause_outcomes, clause.id)
end
