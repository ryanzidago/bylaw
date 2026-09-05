# Run with MIX_ENV=test mix run in an approved QA checkout.
# Set BYLAW_STARTUP_EBIN and BYLAW_STARTUP_OUTPUT to explicit paths.
Code.prepend_path(System.fetch_env!("BYLAW_STARTUP_EBIN"))

modules = Application.spec(Mix.Project.config()[:app], :modules)
true = is_list(modules) and Enum.any?(modules)
{ensure_us, _} = :timer.tc(fn -> Enum.each(modules, &Code.ensure_loaded/1) end)
{load_us, loaded} = :timer.tc(fn -> Bylaw.Contract.StructuralCoverage.load(modules) end)
loaded_memory = :erlang.memory(:total)

{shadow_us, {:ok, shadow}} =
  :timer.tc(fn -> Bylaw.Contract.StructuralCoverage.start_shadow(loaded.classifiers) end)

shadow_memory = :erlang.memory(:total)
{stop_us, :ok} = :timer.tc(fn -> Bylaw.Contract.StructuralCoverage.stop_shadow(shadow) end)
false = :code.is_loaded(shadow)

result = %{
  elixir: System.version(),
  otp: System.otp_release(),
  modules: length(modules),
  classifiers: length(loaded.classifiers),
  clauses: length(loaded.clauses),
  arities: length(loaded.arities),
  warnings: length(loaded.warnings),
  ensure_us: ensure_us,
  load_us: load_us,
  shadow_us: shadow_us,
  stop_us: stop_us,
  beam_bytes_after_load: loaded_memory,
  beam_bytes_after_shadow: shadow_memory,
  metadata_sha256:
    loaded
    |> :erlang.term_to_binary([:deterministic])
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16()
}

File.write!(System.fetch_env!("BYLAW_STARTUP_OUTPUT"), JSON.encode!(result) <> "\n")
IO.inspect(result)
