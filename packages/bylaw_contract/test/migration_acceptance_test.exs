defmodule Bylaw.Contract.MigrationAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract.Example.Partitions
  alias Bylaw.Contract.TestFixtures.Registration
  alias Bylaw.Contract.TestFixtures.SpecTarget
  alias Bylaw.Contract.TestFixtures.UnsupportedReturn

  test "runs on the documented OTP 27-or-newer trace runtime" do
    {otp_release, _rest} = Integer.parse(System.otp_release())

    assert otp_release >= 27
    assert function_exported?(:trace, :session_create, 3)
    assert function_exported?(:trace, :session_destroy, 1)
  end

  test "observes deterministic input classes derived from specs" do
    loaded = Bylaw.Contract.Specs.load([Partitions])
    labels_by_function = Enum.group_by(loaded.input_classes, & &1.function, & &1.label)

    assert labels_by_function.integer_shape == ["negative", "zero", "positive"]
    assert labels_by_function.list_shape == ["empty", "singleton", "multiple"]
    assert labels_by_function.binary_shape == ["empty", "non-empty"]
    assert labels_by_function.boolean_shape == ["false", "true"]
  end

  test "observes finite-range classes and exact boundary values independently" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.Example.Registration])

    assert Bylaw.Contract.Example.Registration.register(17) == :denied
    assert Bylaw.Contract.Example.Registration.register(18) == :allowed

    coverage = Bylaw.Contract.stop(tracer)

    assert hits_by_label(coverage.input_classes, coverage.hits) == %{
             "0..17" => 1,
             "18..120" => 1
           }

    assert hits_by_label(coverage.boundaries, coverage.hits) == %{
             "0" => 0,
             "17" => 1,
             "18" => 1,
             "120" => 0
           }
  end

  test "observes alternatives declared by top-level return unions" do
    {:ok, tracer} = Bylaw.Contract.start([Registration])
    Registration.register(15)
    Registration.register(21)
    coverage = Bylaw.Contract.stop(tracer)
    alternatives = Map.new(coverage.return_alternatives, &{&1.label, &1})

    assert hit_count(
             coverage,
             alternatives["{:ok, Bylaw.Contract.TestFixtures.User.t()}"]
           ) == 1

    assert hit_count(coverage, alternatives["{:error, :underage}"]) == 1
  end

  test "reports source-aware structural clause gaps" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])
    assert Bylaw.Contract.StructuralExample.classify(-1) == :integer
    coverage = Bylaw.Contract.stop(tracer)
    report = report(coverage)

    assert report =~ "Bylaw.Contract structural clause gaps"
    assert report =~ "lib/bylaw/contract/structural_example.ex"
    assert report =~ "def classify(value) when is_integer(value) and value > 0"
    refute report =~ "NOT OBSERVED"
  end

  test "keeps concurrent trace sessions isolated" do
    {:ok, first} = Bylaw.Contract.start([SpecTarget])
    {:ok, second} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])

    SpecTarget.observe(:admin, :web)
    Bylaw.Contract.StructuralExample.classify(:exact)

    second_coverage = Bylaw.Contract.stop(second)
    first_coverage = Bylaw.Contract.stop(first)

    assert first_coverage.calls == %{{SpecTarget, :observe, 2} => 1}

    assert second_coverage.arity_calls[
             {Bylaw.Contract.StructuralExample, :classify, 1}
           ] == 1
  end

  test "distinguishes unassessable alternatives from supported misses in coverage data" do
    {:ok, tracer} = Bylaw.Contract.start([SpecTarget, UnsupportedReturn])
    SpecTarget.observe(:admin, 1)
    UnsupportedReturn.token(true)
    coverage = Bylaw.Contract.stop(tracer)

    opaque_return =
      Enum.find(
        coverage.return_alternatives,
        &(&1.label == "Bylaw.Contract.TestFixtures.RemoteTypes.token()")
      )

    report = report(coverage)

    assert report =~
             "no test exercises this declared input alternative:\n\n" <>
               "      @spec observe"

    assert report =~ "argument 1: :member"
    refute opaque_return.supported?
    assert MapSet.member?(coverage.unknown, opaque_return.id)
    refute report =~ "      return: Bylaw.Contract.TestFixtures.RemoteTypes.token()"
  end

  test "reports missed input alternatives from their typespec source without successful targets" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.Example])
    Bylaw.Contract.Example.greeting(:admin, :short)
    coverage = Bylaw.Contract.stop(tracer)
    output = report(coverage)

    assert output =~ "Bylaw.Contract typespec gaps"

    assert output =~
             "✗ lib/bylaw/contract/example.ex:7\n" <>
               "      Missed input alternative - " <>
               "no test exercises this declared input alternative:\n\n" <>
               "      @spec greeting(audience :: audience(), style :: style()) :: String.t()\n\n" <>
               "      argument 1: :member"

    refute output =~ "HIT"
    refute output =~ "argument 1: :admin"
  end

  test "reports missed range boundaries from their typespec source" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.Example.Registration])
    Bylaw.Contract.Example.Registration.register(17)
    Bylaw.Contract.Example.Registration.register(18)
    coverage = Bylaw.Contract.stop(tracer)
    output = report(coverage)

    assert output =~
             "✗ lib/bylaw/contract/example.ex:27\n" <>
               "      Missed boundary - no test exercises this declared boundary value:\n\n" <>
               "      @spec register(age :: registration_age()) :: :denied | :allowed\n\n" <>
               "      argument 1 boundary: 0"

    refute output =~ "argument 1 boundary: 17"
  end

  test "reports missed return alternatives from their typespec source" do
    {:ok, tracer} = Bylaw.Contract.start([Registration])
    Registration.register(15)
    coverage = Bylaw.Contract.stop(tracer)
    output = report(coverage)

    assert output =~
             "✗ test/support/spec_fixtures.ex:33\n" <>
               "      Missed return alternative - " <>
               "no test exercises this declared return alternative:\n\n" <>
               "      @spec register(age :: non_neg_integer()) ::\n" <>
               "              {:ok, Bylaw.Contract.TestFixtures.User.t()}\n" <>
               "              | {:error, :underage}\n\n" <>
               "      return: {:ok, Bylaw.Contract.TestFixtures.User.t()}"

    refute output =~ "return: {:error, :underage}"
  end

  test "does not misreport unassessable typespec targets as misses" do
    {:ok, tracer} = Bylaw.Contract.start([UnsupportedReturn])
    UnsupportedReturn.token(true)
    coverage = Bylaw.Contract.stop(tracer)

    opaque_return =
      Enum.find(
        coverage.return_alternatives,
        &(&1.label == "Bylaw.Contract.TestFixtures.RemoteTypes.token()")
      )

    output = report(coverage)

    refute opaque_return.supported?
    assert Bylaw.Contract.summary(coverage).unsupported_return_alternatives == 1
    refute output =~ "Unassessable"
    refute output =~ "      return: Bylaw.Contract.TestFixtures.RemoteTypes.token()"
  end

  test "omits unassessable typespec targets from the normal report while preserving assessment data" do
    {:ok, tracer} = Bylaw.Contract.start([Partitions, SpecTarget, UnsupportedReturn])
    Partitions.opaque_shape(1)
    SpecTarget.observe(:admin, 1)
    UnsupportedReturn.token(true)
    coverage = Bylaw.Contract.stop(tracer)
    summary = Bylaw.Contract.summary(coverage)
    output = report(coverage)

    assert summary.unsupported_input_classes > 0
    assert summary.unsupported_return_alternatives > 0
    assert Enum.any?(coverage.input_classes, &(not &1.supported?))
    assert Enum.any?(coverage.return_alternatives, &(not &1.supported?))

    refute output =~ "Unassessable"
    refute output =~ "Bylaw.Contract cannot assess"

    refute output =~
             "      argument 2: Bylaw.Contract.TestFixtures.RemoteTypes.token()"

    refute output =~
             "      return: Bylaw.Contract.TestFixtures.RemoteTypes.token()"
  end

  test "omits unobserved callable arities from the normal report" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])
    Bylaw.Contract.StructuralExample.classify(-1)
    coverage = Bylaw.Contract.stop(tracer)
    output = report(coverage)

    assert Bylaw.Contract.summary(coverage).callable_arities > 0
    assert Map.get(coverage.arity_calls, {Bylaw.Contract.StructuralExample, :optional, 1}, 0) == 0
    refute output =~ "Unobserved callable arities"
    refute output =~ "Bylaw.Contract.StructuralExample.optional/1 — default wrapper"
  end

  test "omits unsupported structural diagnostics from the normal report" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.Example])
    Bylaw.Contract.Example.greeting(:admin, :short)
    coverage = Bylaw.Contract.stop(tracer)

    coverage = %{
      coverage
      | structural_modules: [
          %{module: MyApp.Uninspectable, status: :unsupported, reason: "debug information absent"}
        ]
    }

    output = report(coverage)

    assert Bylaw.Contract.summary(coverage).structural_unsupported == 1
    refute output =~ "Unsupported structural modules"
    refute output =~ "MyApp.Uninspectable"
  end

  test "omits typespec loader warnings from the normal report" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.Example])
    Bylaw.Contract.Example.greeting(:admin, :short)
    coverage = Bylaw.Contract.stop(tracer)

    coverage = %{
      coverage
      | warnings: [
          "MyApp.MissingSpecs has no persisted typespecs",
          "could not load MyApp.MissingModule: :nofile",
          "ignored unsupported spec form MyApp.Unsupported.run/1 clause 1"
        ]
    }

    output = report(coverage)

    assert Bylaw.Contract.summary(coverage).warnings == 3
    refute output =~ "warning: MyApp.MissingSpecs has no persisted typespecs"
    refute output =~ "warning: could not load MyApp.MissingModule"
    refute output =~ "warning: ignored unsupported spec form MyApp.Unsupported.run/1 clause 1"
  end

  test "omits aggregate summaries from the normal report" do
    {:ok, tracer} = Bylaw.Contract.start([SpecTarget, UnsupportedReturn])
    SpecTarget.observe(:admin, 1)
    UnsupportedReturn.token(true)
    coverage = Bylaw.Contract.stop(tracer)
    output = report(coverage)
    summary = Bylaw.Contract.summary(coverage)

    assert summary.missed_input_classes > 0
    assert summary.unsupported_return_alternatives > 0
    assert summary.clauses_selected < summary.clauses
    refute output =~ "Typespec summary:"
    refute output =~ "Typespec assessment:"
    refute output =~ "Structural summary:"
  end

  test "prints no normal report when there are no actionable gaps" do
    {:ok, tracer} = Bylaw.Contract.start([UnsupportedReturn])
    UnsupportedReturn.token(true)
    UnsupportedReturn.token(false)
    coverage = Bylaw.Contract.stop(tracer)

    assert report(coverage) == ""
  end

  test "omits a report section when that section has no actionable gaps" do
    {:ok, tracer} = Bylaw.Contract.start([SpecTarget])
    SpecTarget.observe(:admin, 1)
    coverage = Bylaw.Contract.stop(tracer)
    output = report(coverage)

    assert output =~ "Bylaw.Contract typespec gaps"
    assert output =~ "Missed input alternative"
    refute output =~ "Bylaw.Contract structural clause gaps"
  end

  test "prefixes every normal diagnostic explanation with its category" do
    modules = [
      Bylaw.Contract.Example.Registration,
      Partitions,
      Registration,
      SpecTarget,
      UnsupportedReturn
    ]

    {:ok, tracer} = Bylaw.Contract.start(modules)
    Bylaw.Contract.Example.Registration.register(17)
    Bylaw.Contract.Example.Registration.register(18)
    Partitions.integer_shape(-1)
    Registration.register(15)
    SpecTarget.observe(:admin, 1)
    UnsupportedReturn.token(true)
    coverage = Bylaw.Contract.stop(tracer)
    output = report(coverage)

    assert output =~
             "Missed input alternative - no test exercises this declared input alternative:"

    assert output =~ "Missed input class - no test exercises this typespec-derived input class:"
    assert output =~ "Missed boundary - no test exercises this declared boundary value:"

    assert output =~
             "Missed return alternative - no test exercises this declared return alternative:"

    assert output =~ "Missed function clause - no test exercises this clause:"
    refute output =~ "Unassessable"
    refute output =~ "Bylaw.Contract cannot assess"
  end

  defp hit_count(coverage, target), do: Map.get(coverage.hits, target.id, 0)

  defp hits_by_label(targets, hits) do
    Map.new(targets, &{&1.label, Map.get(hits, &1.id, 0)})
  end

  defp report(coverage) do
    {:ok, device} = StringIO.open("")
    :ok = Bylaw.Contract.print_report(coverage, device)
    {_, output} = StringIO.contents(device)
    output
  end
end
