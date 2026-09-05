defmodule Bylaw.Contract.Report do
  @moduledoc false

  @spec summary(coverage :: map()) :: map()
  def summary(%{status: :incomplete} = coverage), do: Map.take(coverage, [:status, :incomplete])

  def summary(coverage) do
    supported_classes = Enum.filter(coverage.input_classes, & &1.supported?)
    observed_classes = Enum.count(supported_classes, &observed?(&1, coverage))
    observed_boundaries = Enum.count(coverage.boundaries, &observed?(&1, coverage))
    supported_returns = Enum.filter(coverage.return_alternatives, & &1.supported?)
    observed_returns = Enum.count(supported_returns, &observed?(&1, coverage))
    compiler_returns = Map.get(coverage, :compiler_return_alternatives, [])
    supported_compiler_returns = Enum.filter(compiler_returns, & &1.supported?)

    assessable_compiler_returns =
      Enum.reject(supported_compiler_returns, &MapSet.member?(coverage.unknown, &1.id))

    observed_compiler_returns =
      Enum.count(assessable_compiler_returns, &observed?(&1, coverage))

    clauses = Map.get(coverage, :clauses, [])
    clause_outcomes = Map.get(coverage, :clause_outcomes, %{})
    guarded_clauses = Enum.filter(clauses, & &1.guarded?)

    %{
      functions:
        (coverage.input_classes ++ coverage.return_alternatives)
        |> Enum.map(&{&1.module, &1.function, &1.arity})
        |> Enum.uniq()
        |> Enum.count(),
      arguments:
        coverage.input_classes
        |> Enum.map(&{&1.module, &1.function, &1.arity, &1.clause, &1.argument})
        |> Enum.uniq()
        |> Enum.count(),
      calls: Enum.sum(Map.values(coverage.calls)),
      input_classes: Enum.count(coverage.input_classes),
      supported_input_classes: Enum.count(supported_classes),
      observed_input_classes: observed_classes,
      missed_input_classes: Enum.count(supported_classes) - observed_classes,
      unsupported_input_classes:
        Enum.count(coverage.input_classes) - Enum.count(supported_classes),
      boundaries: Enum.count(coverage.boundaries),
      observed_boundaries: observed_boundaries,
      missed_boundaries: Enum.count(coverage.boundaries) - observed_boundaries,
      return_groups:
        coverage.return_alternatives
        |> Enum.map(&{&1.module, &1.function, &1.arity, &1.clause})
        |> Enum.uniq()
        |> Enum.count(),
      return_events: Enum.sum(Map.values(coverage.return_events)),
      return_alternatives: Enum.count(coverage.return_alternatives),
      supported_return_alternatives: Enum.count(supported_returns),
      observed_return_alternatives: observed_returns,
      missed_return_alternatives: Enum.count(supported_returns) - observed_returns,
      unsupported_return_alternatives:
        Enum.count(coverage.return_alternatives) - Enum.count(supported_returns),
      compiler_return_groups:
        compiler_returns
        |> Enum.map(&{&1.module, &1.function, &1.arity})
        |> Enum.uniq()
        |> Enum.count(),
      compiler_call_events: Enum.sum(Map.values(Map.get(coverage, :compiler_calls, %{}))),
      compiler_return_alternatives: Enum.count(compiler_returns),
      supported_compiler_return_alternatives: Enum.count(assessable_compiler_returns),
      observed_compiler_return_alternatives: observed_compiler_returns,
      missed_compiler_return_alternatives:
        Enum.count(assessable_compiler_returns) - observed_compiler_returns,
      unsupported_compiler_return_alternatives:
        Enum.count(compiler_returns) - Enum.count(assessable_compiler_returns),
      compiler_modules: Enum.count(Map.get(coverage, :compiler_modules, [])),
      compiler_unsupported:
        coverage
        |> Map.get(:compiler_modules, [])
        |> Enum.count(&(&1.status == :unsupported)),
      compiler_warnings: Enum.count(Map.get(coverage, :compiler_warnings, [])),
      clauses: Enum.count(clauses),
      clauses_selected: count_observed(clauses, clause_outcomes, :selected),
      clauses_head_matched: count_observed(clauses, clause_outcomes, :head_matches),
      guarded_clauses: Enum.count(guarded_clauses),
      guards_passed: count_observed(guarded_clauses, clause_outcomes, :guard_passes),
      guards_rejected: count_observed(guarded_clauses, clause_outcomes, :guard_rejections),
      callable_arities: Enum.count(Map.get(coverage, :arities, [])),
      arity_calls: Enum.sum(Map.values(Map.get(coverage, :arity_calls, %{}))),
      structural_unsupported:
        coverage
        |> Map.get(:structural_modules, [])
        |> Enum.count(&(&1.status == :unsupported)),
      warnings: Enum.count(coverage.warnings)
    }
  end

  @doc false
  @spec print(coverage :: map(), device :: IO.device(), colors :: boolean()) :: :ok
  def print(coverage, device, colors \\ IO.ANSI.enabled?())

  def print(%{status: :incomplete, incomplete: reasons}, device, _colors) do
    IO.puts(device, "Bylaw.Contract observation incomplete; coverage gaps were not assessed.")

    Enum.each(reasons, fn reason ->
      IO.puts(
        device,
        "#{inspect(reason.check)}: trace queue exceeded #{reason.limit} messages (observed #{reason.observed})."
      )
    end)

    :ok
  end

  def print(%{selected_functions: []}, device, _colors) do
    IO.puts(device, "No functions selected for contract observation.")
  end

  def print(coverage, device, colors) do
    print_typespec_gaps(coverage, device, colors)
    print_compiler_inference_gaps(coverage, device, colors)
    print_structural_coverage(coverage, device, colors)
    :ok
  end

  defp print_typespec_gaps(coverage, device, colors) do
    gaps =
      coverage
      |> typespec_targets()
      |> Enum.filter(fn {_, target} -> assessable?(target, coverage) end)
      |> Enum.reject(fn {_, target} -> observed?(target, coverage) end)

    if Enum.any?(gaps) do
      IO.puts(device, "\nBylaw.Contract typespec gaps")

      gaps
      |> Enum.group_by(fn {_, target} ->
        {target.module, target.function, target.arity}
      end)
      |> Enum.sort_by(fn {mfa, _} -> mfa end)
      |> Enum.each(&print_typespec_group(&1, device, colors))
    end
  end

  defp typespec_targets(coverage) do
    Enum.map(coverage.input_classes, &{:input, &1}) ++
      Enum.map(coverage.boundaries, &{:boundary, &1}) ++
      Enum.map(coverage.return_alternatives, &{:return, &1})
  end

  defp print_typespec_group({{module, function, arity}, targets}, device, colors) do
    IO.puts(device, "\n#{inspect(module)}.#{function}/#{arity}")

    Enum.each(targets, fn {kind, target} ->
      IO.puts(
        device,
        "    #{style("✗", :red, colors)} #{style(typespec_source_location(target), :cyan, colors)}\n" <>
          "      #{target_diagnostic(kind, target, colors)}:\n\n" <>
          style(indent_spec_source(target.spec_source), :faint, colors) <>
          "\n\n" <>
          "      #{style(target_label(kind, target), :red, colors)}\n"
      )
    end)
  end

  defp assessable?(target, coverage) do
    target.supported? and not MapSet.member?(coverage.unknown, target.id)
  end

  defp target_diagnostic(kind, target, colors) do
    "#{style(diagnostic_category(kind, target), :red, colors)} - " <>
      "no test exercises this #{target_description(kind, target)}"
  end

  defp diagnostic_category(:input, %{partition: :union_member}),
    do: "Missed input alternative"

  defp diagnostic_category(:input, _), do: "Missed input class"
  defp diagnostic_category(:boundary, _), do: "Missed boundary"
  defp diagnostic_category(:return, _), do: "Missed return alternative"

  defp target_description(:input, %{partition: :union_member}),
    do: "declared input alternative"

  defp target_description(:input, _), do: "typespec-derived input class"
  defp target_description(:boundary, _), do: "declared boundary value"
  defp target_description(:return, _), do: "declared return alternative"

  defp target_label(:input, target), do: "argument #{target.argument}: #{target.label}"

  defp target_label(:boundary, target),
    do: "argument #{target.argument} boundary: #{target.label}"

  defp target_label(:return, target), do: "return: #{target.label}"

  defp typespec_source_location(%{spec_file: file, spec_line: line}) when is_binary(file) do
    "#{display_file(file)}:#{line}"
  end

  defp typespec_source_location(%{spec_line: line}), do: "line #{line}"

  defp indent_spec_source(source) do
    source
    |> format_spec_source()
    |> String.split("\n")
    |> Enum.map_join("\n", &"      #{&1}")
  end

  defp format_spec_source(source) do
    source
    |> Code.format_string!(line_length: 72)
    |> IO.iodata_to_binary()
    |> String.trim_trailing()
  rescue
    _ -> source
  end

  defp observed?(target, coverage), do: Map.get(coverage.hits, target.id, 0) > 0

  defp print_compiler_inference_gaps(coverage, device, colors) do
    gaps =
      coverage
      |> Map.get(:compiler_return_alternatives, [])
      |> Enum.filter(& &1.supported?)
      |> Enum.reject(&MapSet.member?(coverage.unknown, &1.id))
      |> Enum.reject(&observed?(&1, coverage))

    if Enum.any?(gaps) do
      IO.puts(device, "\nBylaw.Contract compiler-inferred gaps")

      gaps
      |> Enum.group_by(&{&1.module, &1.function, &1.arity})
      |> Enum.sort_by(fn {mfa, _} -> mfa end)
      |> Enum.each(&print_compiler_inference_group(&1, device, colors))
    end
  end

  defp print_compiler_inference_group({{module, function, arity}, alternatives}, device, colors) do
    IO.puts(device, "\n#{inspect(module)}.#{function}/#{arity}")

    Enum.each(alternatives, fn alternative ->
      IO.puts(
        device,
        "    #{style("✗", :red, colors)} compiler-inferred return\n" <>
          "      #{style("Missed compiler-inferred return alternative", :red, colors)} - no test observes:\n\n" <>
          "      #{style("return: #{alternative.label}", :red, colors)}\n"
      )
    end)
  end

  defp print_structural_coverage(coverage, device, colors) do
    clauses = Map.get(coverage, :clauses, [])
    unobserved_clauses = Enum.reject(clauses, &clause_observed?(&1, coverage))

    if Enum.any?(unobserved_clauses) do
      IO.puts(device, "\nBylaw.Contract structural clause gaps")

      unobserved_clauses
      |> Enum.group_by(&{&1.module, &1.function, &1.arity})
      |> Enum.sort_by(fn {mfa, _} -> mfa end)
      |> Enum.each(&print_clause_group(&1, device, colors))
    end
  end

  defp print_clause_group({{module, function, arity}, clauses}, device, colors) do
    IO.puts(device, "\n#{inspect(module)}.#{function}/#{arity}")

    Enum.each(clauses, fn clause ->
      IO.puts(
        device,
        "    #{style("✗", :red, colors)} #{style(source_location(clause), :cyan, colors)}\n" <>
          "      #{style("Missed function clause", :red, colors)} - no test exercises this clause:\n\n" <>
          style(indent_clause_source(clause.source), :red, colors) <> "\n"
      )
    end)
  end

  defp clause_observed?(clause, coverage) do
    coverage.clause_outcomes
    |> Map.get(clause.id, %{})
    |> Map.get(:selected, 0)
    |> Kernel.>(0)
  end

  defp source_location(%{file: file, line: line}) when is_binary(file) do
    "#{display_file(file)}:#{line}"
  end

  defp source_location(%{line: line}), do: "line #{line}"

  defp display_file(file) do
    relative = Path.relative_to(file, File.cwd!())

    if relative == ".." or String.starts_with?(relative, "../") do
      file
    else
      relative
    end
  end

  defp indent_clause_source(source) do
    source
    |> format_clause_source()
    |> String.split("\n")
    |> Enum.map_join("\n", &"      #{&1}")
  end

  defp format_clause_source(source) when byte_size(source) <= 72, do: source

  defp format_clause_source(source) do
    (source <> ", do: nil")
    |> Code.format_string!(line_length: 72)
    |> IO.iodata_to_binary()
    |> String.replace(~r/,\s*do: nil\z/, "")
  rescue
    _ -> source
  end

  defp count_observed(clauses, outcomes, field) do
    Enum.count(clauses, fn clause ->
      Map.get(Map.get(outcomes, clause.id, %{}), field, 0) > 0
    end)
  end

  defp style(text, color, colors) do
    [color, text, :reset]
    |> IO.ANSI.format_fragment(colors)
    |> IO.iodata_to_binary()
  end
end
