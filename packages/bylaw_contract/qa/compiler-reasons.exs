# Run in a fresh VM: elixir qa/compiler-reasons.exs PROJECT APP [BUILD_ENV]
# Static inspection only: this does not run the upstream test suite or instrument modules.
[project, app_name | rest] = System.argv()
build_env = List.first(rest) || "test"
package = Path.expand("..", __DIR__)

{:ok, _, _} =
  Kernel.ParallelCompiler.compile(Path.wildcard(Path.join(package, "lib/**/*.ex")),
    return_diagnostics: true
  )

for path <- Path.wildcard(Path.join(project, "_build/#{build_env}/lib/*/ebin")) do
  Code.prepend_path(path)
end

app = String.to_atom(app_name)
:ok = Application.load(app)
{:ok, modules} = :application.get_key(app, :modules)
if System.get_env("PRELOAD_MODULES") == "1", do: Enum.each(modules, &Code.ensure_loaded/1)
loaded = Bylaw.Contract.CompilerInference.load(modules)

reason_category = fn reason ->
  cond do
    String.starts_with?(reason, "could not decode Elixir checker version") ->
      :descriptor_decode_failure

    String.starts_with?(reason, "compiler inference inspection exceeded") ->
      :inspection_timeout

    String.starts_with?(reason, "unsupported Elixir checker version") ->
      :checker_version

    true ->
      reason
  end
end

specs = Bylaw.Contract.Specs.load(modules)
mfa = fn a -> {a.module, a.function, a.arity} end
claims = MapSet.new(specs.return_alternatives, mfa)
retained = Enum.reject(loaded.return_alternatives, &MapSet.member?(claims, mfa.(&1)))
authored = Enum.filter(retained, &MapSet.member?(loaded.authored_mfas, mfa.(&1)))

unknown_authorship =
  Enum.filter(retained, &MapSet.member?(loaded.unknown_authorship_modules, &1.module))

rules = Enum.group_by(loaded.inference_rules, mfa)
inferable = Enum.filter(authored, & &1.inferable?)
{selected, omitted} = inferable |> Enum.group_by(mfa) |> Enum.sort() |> Enum.split(10)
selected_count = Enum.sum(Enum.map(selected, fn {_, alts} -> length(alts) end))
omitted_count = Enum.sum(Enum.map(omitted, fn {_, alts} -> length(alts) end))

IO.inspect(
  %{
    elixir: System.version(),
    otp: System.otp_release(),
    preloaded: System.get_env("PRELOAD_MODULES") == "1",
    modules: length(modules),
    module_statuses: Enum.frequencies_by(loaded.modules, & &1.status),
    module_reasons:
      loaded.modules
      |> Enum.filter(&(&1.status == :unsupported))
      |> Enum.frequencies_by(&reason_category.(&1.reason)),
    module_reason_examples:
      loaded.modules
      |> Enum.filter(&(&1.status == :unsupported))
      |> Enum.group_by(&reason_category.(&1.reason))
      |> Map.new(fn {reason, [example | _]} ->
        {reason, %{module: example.module, reason: example.reason |> String.split("\n") |> hd()}}
      end),
    raw_alternatives: length(loaded.return_alternatives),
    claimed_by_typespec: length(loaded.return_alternatives) - length(retained),
    generated_excluded_after_decode:
      length(retained) - length(authored) - length(unknown_authorship),
    retained_authored: length(authored),
    unknown_authorship: length(unknown_authorship),
    not_inferable: Enum.count(authored, &(not &1.inferable?)),
    inferable: length(inferable),
    selected_functions: length(selected),
    selected_alternatives: selected_count,
    cap_omitted_alternatives: omitted_count,
    overlapping_flags: %{
      missing_exact_clause_mapping: Enum.count(authored, &(not Map.has_key?(rules, mfa.(&1)))),
      unsupported_return_shape: Enum.count(authored, &(not &1.supported?)),
      non_finite_return_group: Enum.count(authored, &(not &1.runtime_safe?)),
      unsupported_input_group:
        Enum.count(authored, fn a ->
          Enum.any?(Map.get(rules, mfa.(a), []), &(not &1.arguments_supported?))
        end),
      no_single_output_rule:
        Enum.count(authored, fn a ->
          not Enum.any?(Map.get(rules, mfa.(a), []), &(&1.output_ids == MapSet.new([a.id])))
        end)
    }
  },
  limit: :infinity,
  printable_limit: :infinity,
  pretty: true
)
