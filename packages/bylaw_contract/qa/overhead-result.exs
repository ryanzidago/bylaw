[input, expected_mode] = System.argv()
result = input |> File.read!() |> :erlang.binary_to_term()
^expected_mode = result.mode
true = Enum.any?(result.test_states)

expected_checks =
  case expected_mode do
    "disabled" ->
      []

    "typespec" ->
      [Bylaw.Contract.Check.Typespec]

    "structural" ->
      [Bylaw.Contract.Check.FunctionClauses]

    "compiler" ->
      [Bylaw.Contract.Check.ElixirCompiler]

    "all" ->
      [
        Bylaw.Contract.Check.Typespec,
        Bylaw.Contract.Check.FunctionClauses,
        Bylaw.Contract.Check.ElixirCompiler
      ]
  end

checks = if result.coverage, do: Map.keys(result.coverage.checks), else: []
true = Enum.sort(checks) == Enum.sort(expected_checks)

status =
  case {expected_mode, result.coverage} do
    {"disabled", nil} ->
      :disabled

    {mode, coverage} when mode != "disabled" and is_map(coverage) ->
      true = Enum.any?(coverage)
      Map.get(coverage, :status, :complete)
  end

summary = %{
  mode: result.mode,
  checks: Enum.map(checks, &inspect/1),
  elixir: result.elixir,
  otp: result.otp,
  options: inspect(result.options),
  init_us: result.init_us,
  observed_suite_us: result.observed_suite_us,
  stop_us: result.stop_us,
  test_states: result.test_states,
  failures: inspect(result.failures, limit: :infinity, printable_limit: :infinity),
  coverage_status: status,
  incomplete: inspect(result.coverage && Map.get(result.coverage, :incomplete, []))
}

IO.puts(JSON.encode!(summary))
