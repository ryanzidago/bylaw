# MIX_ENV=test mix run this script in the fixture or an approved QA checkout.
# Run outside the unprofiled timing matrix. start/stop complete before profiling ends.
Code.prepend_path(System.fetch_env!("BYLAW_OVERHEAD_EBIN"))
modules = Application.spec(Mix.Project.config()[:app], :modules)
Enum.each(modules, &Code.ensure_loaded!/1)

checks =
  case System.fetch_env!("BYLAW_OVERHEAD_MODE") do
    "typespec" -> [Bylaw.Contract.Check.Typespec]
    "structural" -> [Bylaw.Contract.Check.FunctionClauses]
    "compiler" -> [Bylaw.Contract.Check.ElixirCompiler]
    "defaults" -> [Bylaw.Contract.Check.Typespec, Bylaw.Contract.Check.FunctionClauses]
  end

Mix.Tasks.Profile.Tprof.profile(
  fn ->
    {:ok, tracer} = Bylaw.Contract.start(modules, checks: checks)
    # Finish the workers' synchronous stop before returning to the profiler.
    coverage = Bylaw.Contract.stop(tracer)
    false = Process.alive?(tracer)

    IO.puts(
      "ALLOCATION_SCOPE modules=#{length(modules)} checks=#{inspect(checks)} status=#{Map.get(coverage, :status, :complete)}"
    )
  end,
  type: :memory,
  warmup: false,
  set_on_spawn: true,
  report: :process,
  memory: 1000
)
