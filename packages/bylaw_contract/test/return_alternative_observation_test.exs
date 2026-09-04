defmodule Bylaw.Contract.ReturnAlternativeObservationTest do
  use ExUnit.Case

  alias Bylaw.Contract.TestFixtures.Registration
  alias Bylaw.Contract.TestFixtures.UnsupportedReturn

  test "observes supported return alternatives and counts repeated returns" do
    coverage = observe_registrations([15, 16, 21])

    alternatives = return_alternatives(coverage)
    success = alternatives["{:ok, Bylaw.Contract.TestFixtures.User.t()}"]
    underage = alternatives["{:error, :underage}"]

    assert map_size(alternatives) == 2
    assert hit_count(coverage, success) == 1
    assert hit_count(coverage, underage) == 2
    assert coverage.return_events == %{{Registration, :register, 1} => 3}

    summary = Bylaw.Contract.summary(coverage)
    assert summary.return_groups == 1
    assert summary.return_events == 3
    assert summary.return_alternatives == 2
    assert summary.supported_return_alternatives == 2
    assert summary.observed_return_alternatives == 2
    assert summary.missed_return_alternatives == 0
    assert summary.unsupported_return_alternatives == 0

    assert report(coverage) =~ """
           Bylaw.Contract.TestFixtures.Registration.register/1, return
             Return alternatives: 2/2 supported observed across 3 returns
               HIT   {:ok, Bylaw.Contract.TestFixtures.User.t()} (1 return)
               HIT   {:error, :underage} (2 returns)
           """
  end

  test "reports an unobserved supported return alternative as missed" do
    coverage = observe_registrations([15, 16])
    alternatives = return_alternatives(coverage)

    assert hit_count(coverage, alternatives["{:ok, Bylaw.Contract.TestFixtures.User.t()}"]) == 0
    assert hit_count(coverage, alternatives["{:error, :underage}"]) == 2
    assert Bylaw.Contract.summary(coverage).observed_return_alternatives == 1
    assert Bylaw.Contract.summary(coverage).missed_return_alternatives == 1
  end

  test "reports unsupported return alternatives as unknown" do
    {:ok, tracer} = Bylaw.Contract.start([UnsupportedReturn])
    assert UnsupportedReturn.token(false) == "opaque token"
    coverage = Bylaw.Contract.stop(tracer)

    opaque = return_alternatives(coverage)["Bylaw.Contract.TestFixtures.RemoteTypes.token()"]

    refute opaque.supported?
    assert hit_count(coverage, opaque) == 0
    assert MapSet.member?(coverage.unknown, opaque.id)
    assert Bylaw.Contract.summary(coverage).unsupported_return_alternatives == 1
    assert report(coverage) =~ "????  Bylaw.Contract.TestFixtures.RemoteTypes.token()"
  end

  test "isolates return events between sequential trace sessions" do
    error_coverage = observe_registrations([15])
    success_coverage = observe_registrations([21])

    error_alternatives = return_alternatives(error_coverage)
    success_alternatives = return_alternatives(success_coverage)

    assert hit_count(error_coverage, error_alternatives["{:error, :underage}"]) == 1

    assert hit_count(
             error_coverage,
             error_alternatives["{:ok, Bylaw.Contract.TestFixtures.User.t()}"]
           ) == 0

    assert hit_count(success_coverage, success_alternatives["{:error, :underage}"]) == 0

    assert hit_count(
             success_coverage,
             success_alternatives["{:ok, Bylaw.Contract.TestFixtures.User.t()}"]
           ) == 1
  end

  test "destroying one trace session does not affect another" do
    {:ok, first_tracer} = Bylaw.Contract.start([Registration])
    {:ok, second_tracer} = Bylaw.Contract.start([Registration])

    Registration.register(15)
    first_coverage = Bylaw.Contract.stop(first_tracer)

    Registration.register(21)
    second_coverage = Bylaw.Contract.stop(second_tracer)

    first_alternatives = return_alternatives(first_coverage)
    second_alternatives = return_alternatives(second_coverage)

    assert first_coverage.return_events == %{{Registration, :register, 1} => 1}
    assert hit_count(first_coverage, first_alternatives["{:error, :underage}"]) == 1

    assert second_coverage.return_events == %{{Registration, :register, 1} => 2}
    assert hit_count(second_coverage, second_alternatives["{:error, :underage}"]) == 1

    assert hit_count(
             second_coverage,
             second_alternatives["{:ok, Bylaw.Contract.TestFixtures.User.t()}"]
           ) == 1
  end

  defp observe_registrations(ages) do
    {:ok, tracer} = Bylaw.Contract.start([Registration])
    Enum.each(ages, &Registration.register/1)
    Bylaw.Contract.stop(tracer)
  end

  defp return_alternatives(coverage) do
    Map.new(coverage.return_alternatives, &{&1.label, &1})
  end

  defp hit_count(coverage, alternative), do: Map.get(coverage.hits, alternative.id, 0)

  defp report(coverage) do
    {:ok, device} = StringIO.open("")
    :ok = Bylaw.Contract.print_report(coverage, device)
    {_, output} = StringIO.contents(device)
    output
  end
end
