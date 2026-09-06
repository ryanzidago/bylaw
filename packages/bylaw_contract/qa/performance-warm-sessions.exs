# MIX_ENV=test mix run /absolute/path/to/this/script.exs in the persisted fixture.
# This measures fresh preparation on every session, not prepared-check caching.
Code.require_file(Path.join(__DIR__, "overhead-capture.exs"))

ExUnit.start(
  autorun: false,
  seed: 922_331,
  max_cases: 4,
  formatters: [ExUnit.CLIFormatter, BylawOverheadCapture]
)

previous = Code.compiler_options(docs: false, debug_info: false, infer_signatures: false)
{require_us, loaded} = :timer.tc(fn -> Code.require_file("test/classifiers_test.exs") end)
modules = Enum.map(loaded, &elem(&1, 0))
output = System.fetch_env!("BYLAW_WARM_OUTPUT")

rows =
  for iteration <- 1..3 do
    capture = Path.join(output, "session-#{iteration}.etf")
    System.put_env("BYLAW_OVERHEAD_OUTPUT", capture)
    {run_us, result} = :timer.tc(fn -> ExUnit.run(if iteration == 1, do: [], else: modules) end)
    %{failures: 0, total: 12, excluded: 0, skipped: 0} = result
    true = File.exists?(capture)
    :erlang.garbage_collect()

    %{
      iteration: iteration,
      run_us: run_us,
      result: result,
      capture: capture,
      retained_beam_bytes: :erlang.memory(:total),
      require_us: if(iteration == 1, do: require_us, else: nil)
    }
  end

Code.compiler_options(previous)
File.write!(Path.join(output, "sessions.json"), JSON.encode!(rows) <> "\n")
