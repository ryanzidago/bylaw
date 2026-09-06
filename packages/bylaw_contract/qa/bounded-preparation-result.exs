[input, variant] = System.argv()
result = input |> File.read!() |> :erlang.binary_to_term()

expected_structural =
  if variant == "aggregate",
    do: Bylaw.Contract.Check.FunctionClauses,
    else: BylawBoundedStructuralPreparation

true =
  MapSet.new(Map.keys(result.coverage.checks)) ==
    MapSet.new([Bylaw.Contract.Check.Typespec, expected_structural])

normalized =
  Map.update!(result.coverage, :checks, fn checks ->
    {data, checks} = Map.pop!(checks, expected_structural)
    Map.put(checks, Bylaw.Contract.Check.FunctionClauses, data)
  end)

digest = fn value ->
  value
  |> :erlang.term_to_binary([:deterministic])
  |> then(&:crypto.hash(:sha256, &1))
  |> Base.encode16()
end

summary = %{
  checks: Enum.map(Map.keys(result.coverage.checks), &inspect/1),
  test_states: result.test_states,
  test_identities:
    Enum.sort(result.test_identities)
    |> Enum.map(fn {module, name, line} -> [inspect(module), to_string(name), line] end),
  failures: inspect(result.failures, limit: :infinity, printable_limit: :infinity),
  coverage_status: Map.get(result.coverage, :status, :complete),
  incomplete: inspect(Map.get(result.coverage, :incomplete, [])),
  coverage_sha256: digest.(normalized),
  raw_coverage_sha256: digest.(result.coverage),
  report_sha256: result.report_sha256,
  init_us: result.init_us,
  stop_us: result.stop_us,
  observed_suite_us: result.observed_suite_us,
  ex_unit_timings: result.ex_unit_timings,
  monotonic_boundaries_us: result.monotonic_boundaries_us,
  options: inspect(result.options),
  compiler_options: result.compiler_options,
  elixir: result.elixir,
  otp: result.otp
}

IO.puts(JSON.encode!(summary))
