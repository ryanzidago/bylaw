[repository, reference, source_path, test_path] = System.argv()
Code.prepend_path(Path.expand("../../_build/test/lib/bylaw_contract/ebin", __DIR__))
Mix.start()
Mix.env(:test)
{:ok, _} = Application.ensure_all_started(:ex_unit)

ExUnit.configure(
  bylaw_contract: [
    diff_base: reference,
    diff_paths: [source_path],
    checks: [Bylaw.Contract.Check.Typespec, Bylaw.Contract.Check.FunctionClauses]
  ]
)

System.put_env("BYLAW_CONTRACT_REPORT", "summary")

project =
  case Path.basename(repository) do
    "ecto" -> :ecto
    "livebook" -> :livebook
  end

Mix.Project.in_project(project, repository, [prune_code_paths: false], fn _ ->
  Mix.Task.run("loadconfig")

  Mix.Task.run("test", [
    "--no-compile",
    "--formatter",
    "ExUnit.CLIFormatter",
    "--formatter",
    "Bylaw.Contract.ExUnitFormatter",
    test_path
  ])
end)
