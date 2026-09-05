defmodule Bylaw.Contract.ReportTest do
  use ExUnit.Case

  alias Bylaw.Contract.Example

  test "summarizes a coverage result" do
    coverage = %{
      input_classes: [
        %{
          id: {:input_class, :example, 1},
          module: Example,
          function: :greeting,
          arity: 2,
          clause: 1,
          argument: 1,
          supported?: true
        },
        %{
          id: {:input_class, :example, 2},
          module: Example,
          function: :greeting,
          arity: 2,
          clause: 1,
          argument: 1,
          supported?: true
        }
      ],
      boundaries: [
        %{
          id: {:boundary, :example, 1},
          module: Example,
          function: :greeting,
          arity: 2,
          clause: 1,
          argument: 1,
          supported?: true
        }
      ],
      return_alternatives: [],
      hits: %{{:input_class, :example, 1} => 1, {:boundary, :example, 1} => 1},
      calls: %{{Example, :greeting, 2} => 1},
      return_events: %{},
      unknown: MapSet.new(),
      warnings: []
    }

    assert Bylaw.Contract.summary(coverage) == %{
             functions: 1,
             arguments: 1,
             calls: 1,
             input_classes: 2,
             supported_input_classes: 2,
             observed_input_classes: 1,
             missed_input_classes: 1,
             unsupported_input_classes: 0,
             boundaries: 1,
             observed_boundaries: 1,
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
             clauses: 0,
             clauses_selected: 0,
             clauses_head_matched: 0,
             guarded_clauses: 0,
             guards_passed: 0,
             guards_rejected: 0,
             callable_arities: 0,
             arity_calls: 0,
             structural_unsupported: 0,
             warnings: 0
           }
  end

  test "prints only source-aware structural clause misses" do
    {:ok, tracer} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])
    Bylaw.Contract.StructuralExample.classify(-1)
    coverage = Bylaw.Contract.stop(tracer)

    {:ok, output} = StringIO.open("")
    assert :ok = Bylaw.Contract.print_report(coverage, output, colors: false)
    {_, report} = StringIO.contents(output)

    assert report =~ "Bylaw.Contract structural clause gaps"

    assert report =~
             "✗ lib/bylaw/contract/structural_example.ex:7\n" <>
               "      Missed function clause - no test exercises this clause:\n\n" <>
               "      def classify(value) when is_integer(value) and value > 0"

    refute report =~ "lib/bylaw/contract/structural_example.ex:8\n"
    refute report =~ "NOT OBSERVED"
    refute report =~ "head matched"
    refute report =~ "guard passed"
    refute report =~ "selected"
    refute report =~ "clause 3"

    refute report =~ "Structural summary:"
    refute report =~ "Unobserved callable arities"
    refute report =~ "Bylaw.Contract.StructuralExample.optional/1 — default wrapper"
  end

  test "wraps a long missing clause beneath its diagnostic" do
    source =
      "def classify(%{account: %{status: status}, metadata: %{region: region, role: role}}, " <>
        "options) when status in [:active, :trial] and is_list(options) and region == :eu " <>
        "and role == :admin"

    coverage = %{
      input_classes: [],
      boundaries: [],
      return_alternatives: [],
      hits: %{},
      calls: %{},
      return_events: %{},
      clauses: [
        %{
          id: {:long_clause, 1},
          module: MyApp,
          function: :classify,
          arity: 2,
          file: "lib/my_app.ex",
          line: 12,
          source: source
        }
      ],
      clause_outcomes: %{},
      arities: [],
      arity_calls: %{},
      structural_modules: [],
      warnings: []
    }

    {:ok, output} = StringIO.open("")
    assert :ok = Bylaw.Contract.print_report(coverage, output, colors: false)
    {_, report} = StringIO.contents(output)

    assert report =~
             "✗ lib/my_app.ex:12\n" <>
               "      Missed function clause - no test exercises this clause:\n\n" <>
               "      def classify(\n"

    assert report =~ "            options\n"
    refute report =~ source
  end
end
