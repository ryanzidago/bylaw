[project, ebin, output] = System.argv()
Code.prepend_path(ebin)

{module, function} =
  case project do
    "ecto" -> {Ecto.UUID, :cast}
    "livebook" -> {Livebook.Text.Delta.Operation, :from_compressed}
  end

{:module, ^module} = Code.ensure_loaded(module)
mfa = {module, function, 1}
specs = Bylaw.Contract.Specs.load([module])

entries =
  Enum.map(specs.input_classes ++ specs.boundaries, &{:call, &1}) ++
    Enum.map(specs.return_alternatives, &{:return, &1})

entries =
  Enum.filter(entries, fn {_, target} -> {target.module, target.function, target.arity} == mfa end)

target_result = ProducerTargetPlan.compile(entries)
structural = Bylaw.Contract.StructuralCoverage.load([module])
classifiers = Enum.flat_map(structural.classifiers, & &1.mfa_classifiers)
classifier = Enum.find(classifiers, &(&1.mfa == mfa))

clause_result =
  if classifier, do: ProducerClausePlan.compile(classifier), else: {:error, :missing_classifier}

File.write!(
  output,
  JSON.encode!(%{
    project: project,
    target: inspect(mfa),
    elixir: System.version(),
    otp: :erlang.system_info(:otp_release) |> List.to_string(),
    target_count: length(entries),
    authored_clause_count: if(classifier, do: length(classifier.clauses), else: 0),
    target_result: inspect(target_result),
    clause_result: inspect(clause_result),
    spec_warnings: specs.warnings,
    structural_warnings: structural.warnings,
    observation_status: :not_started
  })
)

IO.puts(File.read!(output))
