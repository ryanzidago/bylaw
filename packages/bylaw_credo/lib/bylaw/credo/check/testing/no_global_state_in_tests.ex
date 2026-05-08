defmodule Bylaw.Credo.Check.Testing.NoGlobalStateInTests do
  @moduledoc """
  Avoid reading or mutating global application and system environment state
  from tests.

  ### Bad

      test "uses config" do
        Application.put_env(:my_app, :feature_enabled?, true)
        assert Feature.enabled?()
      end

  ### Why?

  Application and system environment are shared process-wide state. Tests
  that read or mutate that state can race with each other when the suite
  runs concurrently, especially when a test forgets to restore a value.

  ### Better

      test "uses config" do
        assert Feature.enabled?(%{feature_enabled?: true})
      end

  Prefer passing dependencies or configuration explicitly. If a test needs
  a substitute implementation, use a behaviour-backed module or mock that
  is scoped to the test process.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: """
        Paths containing any configured string are skipped. Use this for test
        support files that intentionally own global test configuration.
        """
      ]
    ]

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
