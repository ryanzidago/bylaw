# Run through run-warm-lifecycle.py for external deadline/memory bounds.
Code.prepend_path(System.fetch_env!("BYLAW_WARM_EBIN"))
Code.require_file(Path.join(__DIR__, "warm-lifecycle-capture.exs"))

ExUnit.start(
  autorun: false,
  seed: 922_331,
  max_cases: 4,
  formatters: [ExUnit.CLIFormatter, BylawWarmLifecycleCapture]
)

fixture? = Mix.Project.config()[:app] == :bylaw_phase_fixture

unless fixture? do
  Code.require_file("test/test_helper.exs")

  ExUnit.configure(
    autorun: false,
    seed: 922_331,
    max_cases: 4,
    formatters: [ExUnit.CLIFormatter, BylawWarmLifecycleCapture]
  )
end

test_options =
  Keyword.merge(
    [docs: false, debug_info: false, infer_signatures: false],
    Mix.Project.config()[:test_elixirc_options] || []
  )

previous = Code.compiler_options(test_options)
scenarios = System.fetch_env!("BYLAW_WARM_SCENARIOS") |> String.split(",")
output = System.fetch_env!("BYLAW_WARM_OUTPUT")

checks =
  case System.fetch_env!("BYLAW_WARM_MODE") do
    "typespec" ->
      [Bylaw.Contract.Check.Typespec]

    "structural" ->
      [Bylaw.Contract.Check.FunctionClauses]

    "compiler" ->
      [Bylaw.Contract.Check.ElixirCompiler]

    "defaults" ->
      [Bylaw.Contract.Check.Typespec, Bylaw.Contract.Check.FunctionClauses]

    "all" ->
      [
        Bylaw.Contract.Check.Typespec,
        Bylaw.Contract.Check.FunctionClauses,
        Bylaw.Contract.Check.ElixirCompiler
      ]
  end

files =
  if fixture?,
    do: [Path.join(__DIR__, "warm-session-tests.exs")],
    else: System.fetch_env!("BYLAW_WARM_TESTS") |> String.split(",")

application_modules = Application.spec(Mix.Project.config()[:app], :modules)
Enum.each(application_modules, &Code.ensure_loaded!/1)
original_md5 = Map.new(application_modules, &{&1, &1.module_info(:md5)})
{load_us, loaded} = :timer.tc(fn -> Enum.flat_map(files, &Code.require_file/1) end)
test_modules = for {module, _} <- loaded, function_exported?(module, :__ex_unit__, 0), do: module
base_hooks = BylawWarmLifecycleCapture.hook_count()

hash = fn value ->
  value
  |> :erlang.term_to_binary([:deterministic])
  |> then(&:crypto.hash(:sha256, &1))
  |> Base.encode16()
end

exact = fn coverage ->
  try do
    if Map.has_key?(coverage.checks, Bylaw.Contract.Check.Typespec) do
      12 = map_size(coverage.calls)
      12 = map_size(coverage.return_events)
      true = Enum.all?(coverage.calls, fn {_, count} -> count == 20 end)
      true = Enum.all?(coverage.return_events, fn {_, count} -> count == 20 end)
      for target <- coverage.return_alternatives, do: 10 = Map.fetch!(coverage.hits, target.id)
    end

    if Map.has_key?(coverage.checks, Bylaw.Contract.Check.FunctionClauses) do
      24 = map_size(coverage.arity_calls)
      48 = length(coverage.clauses)
      true = Enum.all?(coverage.arity_calls, fn {_, count} -> count == 20 end)

      for clause <- coverage.clauses do
        expected =
          cond do
            clause.function == :choose ->
              %{selected: 10, guard_passes: 10, guard_rejections: 0, head_matches: 10}

            clause.position == 1 ->
              %{selected: 10, guard_passes: 10, guard_rejections: 10, head_matches: 20}

            true ->
              %{selected: 10, guard_passes: 20, guard_rejections: 0, head_matches: 20}
          end

        ^expected = Map.fetch!(coverage.clause_outcomes, clause.id)
      end
    end

    if Map.has_key?(coverage.checks, Bylaw.Contract.Check.ElixirCompiler) do
      10 = map_size(coverage.compiler_calls)
      true = Enum.all?(coverage.compiler_calls, fn {_, count} -> count == 20 end)
    end

    true
  rescue
    _ -> false
  end
end

rows =
  for {scenario, iteration} <- Enum.with_index(scenarios, 1), reduce: [] do
    rows ->
      row =
        (fn ->
           System.put_env("BYLAW_WARM_SCENARIO", scenario)
           capture = Path.join(output, "session-#{iteration}.etf")
           System.put_env("BYLAW_WARM_CAPTURE", capture)

           options = [
             checks: checks,
             max_trace_queue: if(scenario == "overflow", do: 64, else: 4096),
             diff_base: false
           ]

           options =
             case scenario do
               "scope_error" ->
                 Keyword.put(options, :diff_base, "missing-warm-fixture-ref")

               "scoped" ->
                 Keyword.put(options, :diff_base, System.fetch_env!("BYLAW_WARM_DIFF_BASE"))

               _ ->
                 options
             end

           ExUnit.configure(bylaw_contract: options)

           {run_us, test_result} =
             :timer.tc(fn -> ExUnit.run(if iteration == 1, do: [], else: test_modules) end)

           captured = capture |> File.read!() |> :erlang.binary_to_term()
           c = captured.coverage

           restored =
             Enum.all?(original_md5, fn {module, md5} -> module.module_info(:md5) == md5 end)

           cleanup = Map.put(captured.cleanup, :original_modules_restored, restored)
           cleanup = Map.update!(cleanup, :all_released, &(&1 and restored))
           {:ok, device} = StringIO.open("")
           if c, do: Bylaw.Contract.print_report(c, device, colors: false)
           {_, report} = StringIO.contents(device)
           StringIO.close(device)

           %{
             iteration: iteration,
             scenario: scenario,
             os_pid: System.pid(),
             test_result: test_result,
             coverage_status:
               if(c, do: Map.get(c, :status, :complete), else: :initialization_error),
             incomplete: inspect(c && Map.get(c, :incomplete, [])),
             error: inspect(captured.error),
             cleanup: cleanup,
             completion: captured.completion,
             observer: captured.observer,
             workers: captured.workers,
             compiler_options:
               Map.take(Code.compiler_options(), [:docs, :debug_info, :infer_signatures]),
             hooks: captured.hooks - base_hooks,
             coverage_sha256: hash.(c),
             report_sha256: hash.(report),
             exact_fixture_counts: if(fixture? and c, do: exact.(c), else: nil),
             load_us: if(iteration == 1, do: load_us, else: nil),
             run_us: run_us,
             init_us: captured.init_us,
             stop_us: captured.stop_us
           }
         end).()

      :erlang.garbage_collect()
      row = Map.put(row, :post_capture_gc_beam_bytes, :erlang.memory(:total))

      rows = rows ++ [row]

      aggregate =
        if Enum.any?(
             rows,
             &(&1.test_result.failures > 0 or &1.coverage_status != :complete or
                 not &1.cleanup.all_released)
           ), do: 2, else: 0

      File.write!(
        Path.join(output, "sessions.json"),
        JSON.encode!(%{sessions: rows, aggregate_exit_code: aggregate}) <> "\n"
      )

      rows
  end

Code.compiler_options(previous)

if Enum.any?(
     rows,
     &(&1.test_result.failures > 0 or &1.coverage_status != :complete or
         not &1.cleanup.all_released)
   ),
   do: exit({:shutdown, 2})
