defmodule Bylaw.Contract.Report do
  @moduledoc false

  @spec summary(coverage :: map()) :: map()
  def summary(coverage) do
    supported_classes = Enum.filter(coverage.input_classes, & &1.supported?)
    observed_classes = Enum.count(supported_classes, &observed?(&1, coverage))
    observed_boundaries = Enum.count(coverage.boundaries, &observed?(&1, coverage))
    supported_returns = Enum.filter(coverage.return_alternatives, & &1.supported?)
    observed_returns = Enum.count(supported_returns, &observed?(&1, coverage))
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

  @spec print(coverage :: map(), device :: IO.device()) :: :ok
  def print(coverage, device) do
    input_groups =
      coverage.input_classes
      |> Enum.group_by(&input_group_key/1)
      |> Enum.sort_by(fn {key, _} -> key end)

    return_groups =
      coverage.return_alternatives
      |> Enum.group_by(&return_group_key/1)
      |> Enum.sort_by(fn {key, _} -> key end)

    IO.puts(device, "\nBylaw.Contract typespec-derived coverage")

    if Enum.empty?(input_groups) and Enum.empty?(return_groups) do
      IO.puts(device, "No input types or top-level return unions found.")
    else
      Enum.each(input_groups, &print_input_group(&1, coverage, device))
      Enum.each(return_groups, &print_return_group(&1, coverage, device))
      print_summary(coverage, device)
    end

    print_structural_coverage(coverage, device)

    Enum.each(coverage.warnings, &IO.puts(device, "warning: #{&1}"))
    :ok
  end

  defp print_input_group(
         {{module, function, arity, clause, argument} = key, classes},
         coverage,
         device
       ) do
    supported = Enum.filter(classes, & &1.supported?)
    observed_count = Enum.count(supported, &observed?(&1, coverage))
    call_count = Map.get(coverage.calls, {module, function, arity}, 0)

    clause_suffix =
      if multiple_clauses?(coverage.input_classes, module, function, arity) do
        " clause #{clause}"
      else
        ""
      end

    IO.puts(
      device,
      "\n#{inspect(module)}.#{function}/#{arity}#{clause_suffix}, argument #{argument}"
    )

    IO.puts(
      device,
      "  Input classes: #{observed_count}/#{Enum.count(supported)} supported observed across " <>
        "#{call_count} calls"
    )

    Enum.each(classes, &print_target(&1, coverage, device, "call"))

    boundaries = Enum.filter(coverage.boundaries, &(input_group_key(&1) == key))

    if Enum.any?(boundaries) do
      boundary_hits = Enum.count(boundaries, &observed?(&1, coverage))
      IO.puts(device, "  Boundary values: #{boundary_hits}/#{Enum.count(boundaries)} observed")
      Enum.each(boundaries, &print_target(&1, coverage, device, "call"))
    end
  end

  defp print_return_group({{module, function, arity, clause}, alternatives}, coverage, device) do
    supported = Enum.filter(alternatives, & &1.supported?)
    observed_count = Enum.count(supported, &observed?(&1, coverage))
    return_count = Map.get(coverage.return_events, {module, function, arity}, 0)

    clause_suffix =
      if multiple_clauses?(coverage.return_alternatives, module, function, arity) do
        " clause #{clause}"
      else
        ""
      end

    IO.puts(device, "\n#{inspect(module)}.#{function}/#{arity}#{clause_suffix}, return")

    IO.puts(
      device,
      "  Return alternatives: #{observed_count}/#{Enum.count(supported)} supported observed across " <>
        "#{return_count} returns"
    )

    Enum.each(alternatives, &print_target(&1, coverage, device, "return"))
  end

  defp print_summary(coverage, device) do
    summary = summary(coverage)

    input_percentage = percentage(summary.observed_input_classes, summary.supported_input_classes)

    return_percentage =
      percentage(summary.observed_return_alternatives, summary.supported_return_alternatives)

    input_unsupported = unsupported_suffix(summary.unsupported_input_classes)
    return_unsupported = unsupported_suffix(summary.unsupported_return_alternatives)

    boundary_suffix =
      if summary.boundaries > 0 do
        "; #{summary.observed_boundaries}/#{summary.boundaries} boundaries observed"
      else
        ""
      end

    IO.puts(
      device,
      "\nInput summary: #{summary.observed_input_classes}/#{summary.supported_input_classes} " <>
        "supported input classes observed " <>
        "(#{:erlang.float_to_binary(input_percentage, decimals: 1)}%)#{input_unsupported}" <>
        boundary_suffix
    )

    IO.puts(
      device,
      "Return summary: #{summary.observed_return_alternatives}/" <>
        "#{summary.supported_return_alternatives} supported return alternatives observed " <>
        "(#{:erlang.float_to_binary(return_percentage, decimals: 1)}%)#{return_unsupported}"
    )
  end

  defp print_target(target, coverage, device, observation) do
    hits = Map.get(coverage.hits, target.id, 0)

    marker =
      cond do
        hits > 0 -> "HIT "
        not target.supported? or MapSet.member?(coverage.unknown, target.id) -> "????"
        true -> "MISS"
      end

    suffix =
      if hits > 0 do
        " (#{hits} #{observation}#{plural(hits)})"
      else
        ""
      end

    IO.puts(device, "    #{marker}  #{target.label}#{suffix}")
  end

  defp observed?(target, coverage), do: Map.get(coverage.hits, target.id, 0) > 0

  defp input_group_key(target) do
    {target.module, target.function, target.arity, target.clause, target.argument}
  end

  defp return_group_key(target) do
    {target.module, target.function, target.arity, target.clause}
  end

  defp print_structural_coverage(coverage, device) do
    clauses = Map.get(coverage, :clauses, [])
    unobserved_clauses = Enum.reject(clauses, &clause_observed?(&1, coverage))
    arities = Map.get(coverage, :arities, [])
    unsupported = unsupported_modules(coverage)

    IO.puts(device, "\nBylaw.Contract structural clause gaps")

    cond do
      Enum.empty?(clauses) ->
        IO.puts(device, "No supported user-authored def/defp clauses found.")

      Enum.empty?(unobserved_clauses) ->
        IO.puts(
          device,
          "All #{Enum.count(clauses)} authored clauses were exercised by this test run."
        )

      true ->
        unobserved_clauses
        |> Enum.group_by(&{&1.module, &1.function, &1.arity})
        |> Enum.sort_by(fn {mfa, _} -> mfa end)
        |> Enum.each(&print_clause_group(&1, device))

        print_structural_summary(unobserved_clauses, clauses, device)
    end

    print_arities(arities, coverage, device)

    if Enum.any?(unsupported) do
      IO.puts(
        device,
        "\nUnsupported structural modules: " <>
          Enum.map_join(unsupported, ", ", &inspect(&1.module))
      )
    end
  end

  defp print_clause_group({{module, function, arity}, clauses}, device) do
    IO.puts(device, "\n#{inspect(module)}.#{function}/#{arity}")

    Enum.each(clauses, fn clause ->
      IO.puts(
        device,
        "    ✗ #{source_location(clause)}\n" <>
          "      no test exercises this clause:\n\n" <>
          indent_clause_source(clause.source) <> "\n"
      )
    end)
  end

  defp print_structural_summary(unobserved_clauses, clauses, device) do
    IO.puts(
      device,
      "Structural summary: #{Enum.count(unobserved_clauses)} of #{Enum.count(clauses)} authored clauses " <>
        "were not exercised by this test run"
    )
  end

  defp print_arities([], _, _), do: :ok

  defp print_arities(arities, coverage, device) do
    unobserved_arities =
      Enum.filter(arities, &(Map.get(coverage.arity_calls, &1.id, 0) == 0))

    if Enum.any?(unobserved_arities) do
      IO.puts(device, "\nUnobserved callable arities")

      Enum.each(unobserved_arities, fn arity ->
        kind =
          if arity.default_wrapper? do
            "default wrapper"
          else
            "authored"
          end

        visibility = Atom.to_string(arity.visibility)

        IO.puts(
          device,
          "    #{inspect(arity.module)}.#{arity.function}/#{arity.arity} — #{kind}, #{visibility}"
        )
      end)
    end
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

  defp unsupported_modules(coverage) do
    coverage
    |> Map.get(:structural_modules, [])
    |> Enum.filter(&(&1.status == :unsupported))
  end

  defp count_observed(clauses, outcomes, field) do
    Enum.count(clauses, fn clause ->
      Map.get(Map.get(outcomes, clause.id, %{}), field, 0) > 0
    end)
  end

  defp multiple_clauses?(targets, module, function, arity) do
    targets
    |> Enum.filter(&(&1.module == module and &1.function == function and &1.arity == arity))
    |> Enum.uniq_by(& &1.clause)
    |> Enum.count() > 1
  end

  defp percentage(_, 0), do: 0.0
  defp percentage(observed, supported), do: observed * 100.0 / supported

  defp unsupported_suffix(0), do: ""
  defp unsupported_suffix(count), do: "; #{count} unsupported"

  defp plural(1), do: ""
  defp plural(_), do: "s"
end
