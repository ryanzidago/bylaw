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

  test "distinguishes unsupported alternatives from supported unobserved alternatives" do
    {:ok, tracer} = Bylaw.Contract.start([SpecTarget, UnsupportedReturn])
    SpecTarget.observe(:admin, 1)
    UnsupportedReturn.token(true)
    coverage = Bylaw.Contract.stop(tracer)
    report = report(coverage)

    assert report =~ "MISS  :member"
    assert report =~ "????  Bylaw.Contract.TestFixtures.RemoteTypes.token()"
    refute report =~ "MISS  Bylaw.Contract.TestFixtures.RemoteTypes.token()"
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
