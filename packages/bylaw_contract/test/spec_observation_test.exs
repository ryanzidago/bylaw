defmodule Bylaw.Contract.SpecObservationTest do
  use ExUnit.Case

  alias Bylaw.Contract.Example
  alias Bylaw.Contract.Example.Partitions
  alias Bylaw.Contract.TestFixtures.SpecTarget

  test "the demo suite intentionally exercises only part of the audience union" do
    assert Example.greeting(:admin, :short) == "Welcome, admin"
    assert Example.greeting({:guest, 7}, :long) == "Welcome, guest number 7"
  end

  test "extracts union input classes through local type aliases" do
    loaded = Bylaw.Contract.Specs.load([Example])

    classes_by_argument = Enum.group_by(loaded.input_classes, & &1.argument, & &1.label)

    assert classes_by_argument[1] == [
             ":admin",
             ":member",
             "{:guest, non_neg_integer()}"
           ]

    assert classes_by_argument[2] == [":short", ":long"]
    assert Enum.all?(loaded.input_classes, & &1.supported?)
    assert Enum.empty?(loaded.boundaries)
  end

  test "extracts union constraints from bounded specs" do
    loaded = Bylaw.Contract.Specs.load([Bylaw.Contract.Example.Bounded])

    assert Enum.map(loaded.input_classes, & &1.label) == [":left", ":right"]
    assert Enum.map(loaded.return_alternatives, & &1.label) == [":left", ":right"]
    assert Enum.empty?(loaded.warnings)
  end

  test "tracks input classes independently and preserves unknown members programmatically" do
    calls = [{:admin, 1}, {{:guest, 7}, 2}]

    coverage = observe(calls)
    reverse_coverage = observe(Enum.reverse(calls))

    assert coverage == reverse_coverage
    assert Enum.empty?(coverage.warnings)
    assert coverage.calls == %{{SpecTarget, :observe, 2} => 2}

    input_classes =
      Map.new(coverage.input_classes, fn input_class ->
        {{input_class.argument, input_class.label}, input_class}
      end)

    assert hit_count(coverage, input_classes[{1, ":admin"}]) == 1
    assert hit_count(coverage, input_classes[{1, ":member"}]) == 0
    assert hit_count(coverage, input_classes[{1, "{:guest, non_neg_integer()}"}]) == 1

    assert hit_count(coverage, input_classes[{2, ":web"}]) == 0
    assert hit_count(coverage, input_classes[{2, "pos_integer()"}]) == 2
    assert hit_count(coverage, input_classes[{2, "number()"}]) == 2

    opaque = input_classes[{2, "Bylaw.Contract.TestFixtures.RemoteTypes.token()"}]
    refute opaque.supported?
    assert hit_count(coverage, opaque) == 0
    assert MapSet.member?(coverage.unknown, opaque.id)

    assert Bylaw.Contract.summary(coverage) == %{
             functions: 1,
             arguments: 2,
             calls: 2,
             input_classes: 7,
             supported_input_classes: 6,
             observed_input_classes: 4,
             missed_input_classes: 2,
             unsupported_input_classes: 1,
             boundaries: 0,
             observed_boundaries: 0,
             missed_boundaries: 0,
             return_groups: 0,
             return_events: 0,
             return_alternatives: 0,
             supported_return_alternatives: 0,
             observed_return_alternatives: 0,
             missed_return_alternatives: 0,
             unsupported_return_alternatives: 0,
             compiler_return_groups: 0,
             compiler_call_events: 0,
             compiler_return_alternatives: 0,
             supported_compiler_return_alternatives: 0,
             observed_compiler_return_alternatives: 0,
             missed_compiler_return_alternatives: 0,
             unsupported_compiler_return_alternatives: 0,
             compiler_modules: 0,
             compiler_unsupported: 0,
             compiler_warnings: 0,
             clauses: 1,
             clauses_selected: 1,
             clauses_head_matched: 1,
             guarded_clauses: 0,
             guards_passed: 0,
             guards_rejected: 0,
             callable_arities: 1,
             arity_calls: 2,
             structural_unsupported: 0,
             warnings: 0
           }

    output = report(coverage)

    assert output =~
             "no test exercises this declared input alternative:\n\n" <>
               "      @spec observe"

    assert output =~ "argument 1: :member"
    assert output =~ "argument 2: :web"

    refute output =~ "Bylaw.Contract cannot assess"
    refute output =~ "argument 2: Bylaw.Contract.TestFixtures.RemoteTypes.token()"
    refute output =~ "HIT"
  end

  test "derives deterministic classes for standard input types" do
    loaded = Bylaw.Contract.Specs.load([Partitions])
    labels_by_function = Enum.group_by(loaded.input_classes, & &1.function, & &1.label)

    assert labels_by_function.integer_shape == ["negative", "zero", "positive"]
    assert labels_by_function.list_shape == ["empty", "singleton", "multiple"]
    assert labels_by_function.binary_shape == ["empty", "non-empty"]
    assert labels_by_function.boolean_shape == ["false", "true"]

    assert MapSet.new(labels_by_function.nullable_shape) ==
             MapSet.new(["nil", "integer()"])

    opaque_class = Enum.find(loaded.input_classes, &(&1.function == :opaque_shape))
    refute opaque_class.supported?
  end

  test "collapses duplicate range partitions and boundaries" do
    loaded = Bylaw.Contract.Specs.load([Partitions])

    short_classes =
      for input_class <- loaded.input_classes,
          input_class.function == :short_range,
          do: input_class.label

    short_boundaries =
      Enum.filter(loaded.boundaries, &(&1.function == :short_range))

    assert short_classes == ["minimum (1)", "maximum (2)"]
    assert Enum.map(short_boundaries, & &1.value) == [1, 2]
  end

  test "reports range classes and exact boundaries independently" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.Example.Registration])

    assert Bylaw.Contract.Example.Registration.register(17) == :denied
    assert Bylaw.Contract.Example.Registration.register(17) == :denied
    assert Bylaw.Contract.Example.Registration.register(18) == :allowed

    coverage = Bylaw.Contract.stop(tracer)
    class_hits = hits_by_label(coverage.input_classes, coverage.hits)
    boundary_hits = hits_by_label(coverage.boundaries, coverage.hits)

    assert class_hits == %{"0..17" => 2, "18..120" => 1}
    assert boundary_hits == %{"0" => 0, "17" => 2, "18" => 1, "120" => 0}

    summary = Bylaw.Contract.summary(coverage)
    assert summary.observed_input_classes == 2
    assert summary.missed_input_classes == 0
    assert summary.observed_boundaries == 2
    assert summary.missed_boundaries == 2

    {:ok, device} = StringIO.open("")
    assert Bylaw.Contract.print_report(coverage, device) == :ok
    {_, report} = StringIO.contents(device)

    assert report =~ "no test exercises this declared boundary value"
    assert report =~ "argument 1 boundary: 0"
    assert report =~ "argument 1 boundary: 120"
    refute report =~ "argument 1 boundary: 17"
    refute report =~ "argument 1 boundary: 18"
  end

  test "keeps unsupported input shapes unknown and out of the normal report" do
    loaded = Bylaw.Contract.Specs.load([Partitions])
    opaque_class = Enum.find(loaded.input_classes, &(&1.function == :opaque_shape))

    refute opaque_class.supported?
    assert Bylaw.Contract.TypeMatcher.match(1, opaque_class.match_type) == :unknown

    coverage = %{
      input_classes: [opaque_class],
      boundaries: [],
      return_alternatives: [],
      hits: %{},
      calls: %{},
      return_events: %{},
      unknown: MapSet.new(),
      warnings: []
    }

    {:ok, device} = StringIO.open("")
    Bylaw.Contract.print_report(coverage, device)
    {_, report} = StringIO.contents(device)

    assert report == ""
    refute report =~ "Bylaw.Contract cannot assess"
    refute report =~ "argument 1: token()"
    refute report =~ "no test exercises this typespec-derived input class"
  end

  test "observes standard partitions and keeps their counts independent" do
    {:ok, tracer} = Bylaw.Contract.start([Partitions])

    Partitions.integer_shape(-1)
    Partitions.integer_shape(0)
    Partitions.integer_shape(1)
    Partitions.integer_shape(1)
    Partitions.list_shape([])
    Partitions.list_shape([1])
    Partitions.list_shape([1, 2])
    Partitions.binary_shape("")
    Partitions.binary_shape("bylaw_contract")
    Partitions.boolean_shape(false)
    Partitions.boolean_shape(true)
    Partitions.nullable_shape(nil)
    Partitions.nullable_shape(1)
    Partitions.short_range(1)
    Partitions.short_range(2)
    Partitions.opaque_shape(1)

    coverage = Bylaw.Contract.stop(tracer)
    classes_by_function = Enum.group_by(coverage.input_classes, & &1.function)

    assert hits_by_label(classes_by_function.integer_shape, coverage.hits) == %{
             "negative" => 1,
             "positive" => 2,
             "zero" => 1
           }

    assert hits_by_label(classes_by_function.list_shape, coverage.hits) == %{
             "empty" => 1,
             "multiple" => 1,
             "singleton" => 1
           }

    assert hits_by_label(classes_by_function.binary_shape, coverage.hits) == %{
             "empty" => 1,
             "non-empty" => 1
           }

    assert hits_by_label(classes_by_function.boolean_shape, coverage.hits) == %{
             "false" => 1,
             "true" => 1
           }

    assert hits_by_label(classes_by_function.nullable_shape, coverage.hits) == %{
             "integer()" => 1,
             "nil" => 1
           }

    opaque_class = hd(classes_by_function.opaque_shape)
    assert MapSet.member?(coverage.unknown, opaque_class.id)
  end

  defp observe(calls) do
    {:ok, tracer} = Bylaw.Contract.start([SpecTarget])
    Enum.each(calls, fn {audience, channel} -> SpecTarget.observe(audience, channel) end)
    Bylaw.Contract.stop(tracer)
  end

  defp hit_count(coverage, alternative), do: Map.get(coverage.hits, alternative.id, 0)

  defp report(coverage) do
    {:ok, device} = StringIO.open("")
    :ok = Bylaw.Contract.print_report(coverage, device)
    {_, output} = StringIO.contents(device)
    output
  end

  defp hits_by_label(targets, hits) do
    Map.new(targets, &{&1.label, Map.get(hits, &1.id, 0)})
  end
end
