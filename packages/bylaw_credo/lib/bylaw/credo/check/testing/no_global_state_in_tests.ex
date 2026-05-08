defmodule Bylaw.Credo.Check.Testing.NoGlobalStateInTests do
  @moduledoc """
  Disallows `Application.put_env/3`, `Application.put_env/4`,
  `Application.delete_env/2`, `Application.delete_env/3`,
  `Application.get_env/2`, `Application.get_env/3`,
  `Application.fetch_env/2`, `Application.fetch_env!/2`,
  `System.put_env/1`, `System.put_env/2`, `System.delete_env/1`,
  `System.get_env/0`, `System.get_env/1`, and `System.get_env/2`
  in test files.

  Reading or mutating global state in tests leads to race conditions
  when tests run concurrently. Use dependency injection or mock
  behaviours instead.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [excluded_paths: []]

  @application_functions ~w(put_env delete_env get_env fetch_env fetch_env!)a
  @system_functions ~w(put_env delete_env get_env)a

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if test_file?(source_file.filename) and not excluded?(source_file.filename, excluded_paths) do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end

  defp test_file?(filename) do
    String.ends_with?(filename, "_test.exs")
  end

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &String.contains?(filename, &1))
  end

  # Application.func(...)
  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:Application]}, func]}, meta, _args} =
           ast,
         issues,
         issue_meta
       )
       when func in @application_functions do
    {ast, [issue_for(issue_meta, meta[:line] || 0, "Application.#{func}") | issues]}
  end

  # System.func(...)
  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:System]}, func]}, meta, _args} = ast,
         issues,
         issue_meta
       )
       when func in @system_functions do
    {ast, [issue_for(issue_meta, meta[:line] || 0, "System.#{func}") | issues]}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Avoid `#{trigger}` in tests - it mutates/reads global state and causes race conditions. Use dependency injection instead.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
