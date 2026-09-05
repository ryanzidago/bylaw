# Validate and summarize trusted local captures from compiler-cap-capture.exs.
rows =
  for file <- System.argv() do
    r = File.read!(file) |> :erlang.binary_to_term()
    app = Atom.to_string(r.app)
    cap = r.cap
    c = r.coverage
    true = Enum.empty?(r.failures)
    true = Enum.any?(r.tests)

    false =
      Enum.any?(
        c.compiler_warnings,
        &String.starts_with?(&1, "compiler call inference unsupported")
      )

    eligible = MapSet.new(r.eligible)
    selected = MapSet.new(r.selected)
    true = MapSet.subset?(selected, eligible)
    chosen = r.eligible |> Enum.take(cap) |> MapSet.new()
    omitted = MapSet.difference(eligible, chosen)

    native_selected =
      r.counts
      |> Enum.filter(fn {mfa, count} ->
        MapSet.member?(selected, mfa) and is_integer(count) and count > 0
      end)
      |> Map.new()

    true = native_selected == c.compiler_calls
    alts = c.compiler_return_alternatives

    selected_alts =
      Enum.filter(
        alts,
        &(&1.inferable? and MapSet.member?(selected, {&1.module, &1.function, &1.arity}))
      )

    assessable = Enum.reject(alts, &MapSet.member?(c.unknown, &1.id))
    hits = Enum.filter(assessable, &(Map.get(c.hits, &1.id, 0) > 0))
    true = length(alts) == length(assessable) + MapSet.size(c.unknown)
    mfa = fn value -> inspect(value) end

    %{
      app: app,
      cap: cap,
      test_states: r.tests,
      eligible_functions: length(r.eligible),
      eligible_alternatives: Enum.count(alts, & &1.inferable?),
      chosen_functions: MapSet.size(chosen),
      selected_functions: length(r.selected),
      selected_alternatives: length(selected_alts),
      cap_omitted_functions: MapSet.size(omitted),
      cap_omitted_alternatives:
        Enum.count(
          alts,
          &(&1.inferable? and MapSet.member?(omitted, {&1.module, &1.function, &1.arity}))
        ),
      called_eligible_functions: Enum.count(r.counts, fn {_, n} -> is_integer(n) and n > 0 end),
      observed_functions: map_size(c.compiler_calls),
      assessable_alternatives: length(assessable),
      hit_alternatives: length(hits),
      missed_alternatives: length(assessable) - length(hits),
      unknown_alternatives: MapSet.size(c.unknown),
      native_selected_counts_equal_compiler: true,
      native_counts: Map.new(r.counts, fn {key, value} -> {mfa.(key), value} end),
      selected: Enum.map(Enum.sort(r.selected), mfa),
      eligible: Enum.map(r.eligible, mfa),
      module_statuses: Enum.frequencies_by(c.compiler_modules, & &1.status),
      warnings: c.compiler_warnings,
      init_us: r.init_us,
      suite_us: r.suite_us,
      memory_before_bytes: r.memory_before,
      memory_after_bytes: r.memory_after,
      memory_end_bytes: r.memory_end,
      alternative_flags:
        alts |> Enum.frequencies_by(&inspect({&1.supported?, &1.runtime_safe?, &1.inferable?}))
    }
  end

IO.puts(JSON.encode!(rows))
