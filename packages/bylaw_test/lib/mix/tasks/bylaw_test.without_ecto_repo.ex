defmodule Mix.Tasks.BylawTest.WithoutEctoRepo do
  use Mix.Task

  @shortdoc "Runs consumer tests while selected Ecto repos stay stopped"
  @moduledoc """
  Runs conventional `*_without_repo_test.exs` files, or explicit `.exs` files,
  without starting selected Ecto repos. Optional `without_repo_helper.exs`
  files are loaded for participating test roots before the selected tests.

  `--repo MyApp.Repo` selects a repo by its ordinary Elixir module name. Repeating
  the option replaces the consuming application's configured `:ecto_repos`.
  """

  @doc "Runs selected consumer tests without starting selected Ecto repos."
  @spec run(list(String.t())) :: :ok | no_return()
  @impl Mix.Task
  def run(args) do
    unless Mix.env() == :test do
      Mix.raise("bylaw_test.without_ecto_repo must run with MIX_ENV=test")
    end

    Mix.Task.run("app.config")

    {options, files, invalid} = OptionParser.parse(args, strict: [repo: :keep])

    if invalid != [] do
      Mix.raise("invalid arguments: #{inspect(invalid)}")
    end

    repos = selected_repos(options)
    validate_repos!(repos)
    roots = test_roots()
    selected_files = selected_files!(files, roots)
    participating_roots = participating_roots(selected_files, roots)

    Bylaw.Test.activate_run(repos)

    try do
      ExUnit.start(autorun: false)
      validate_repos!(repos)
      Enum.each(participating_roots, &load_helper/1)
      validate_repos!(repos)

      Enum.each(selected_files, &Code.require_file/1)
      result = ExUnit.run()

      validate_repos!(repos)
      ensure_tests_ran!(result)

      if result.failures > 0 do
        Mix.raise("#{result.failures} of #{result.total} tests failed")
      end

      :ok
    after
      Bylaw.Test.deactivate_run()
    end
  end

  defp selected_repos(options) do
    supplied = Keyword.get_values(options, :repo)

    repos =
      if supplied == [] do
        Application.get_env(Mix.Project.config()[:app], :ecto_repos, [])
      else
        Enum.map(supplied, &parse_repo!/1)
      end

    unless is_list(repos) and Enum.all?(repos, &is_atom/1) do
      Mix.raise("configured :ecto_repos must be a list of repo modules")
    end

    if Enum.empty?(repos) do
      Mix.raise("configure at least one repo in :ecto_repos or pass --repo")
    end

    Enum.uniq(repos)
  end

  defp parse_repo!(name) do
    if Regex.match?(~r/^[A-Z][A-Za-z0-9_]*(\.[A-Z][A-Za-z0-9_]*)*$/, name) do
      Module.concat(String.split(name, "."))
    else
      Mix.raise("invalid repo module name #{inspect(name)}")
    end
  end

  defp validate_repos!(repos) do
    Enum.each(repos, fn repo ->
      valid = Code.ensure_loaded?(repo) and function_exported?(repo, :__adapter__, 0)

      unless valid do
        Mix.raise("#{inspect(repo)} is not a loaded Ecto repo module")
      end

      if Process.whereis(repo) do
        Mix.raise("#{inspect(repo)} is started during a without-repo test run")
      end
    end)
  end

  defp test_roots do
    roots = Mix.Project.config()[:test_paths] || ["test"]
    roots |> Enum.map(&canonical_path/1) |> Enum.uniq()
  end

  defp selected_files!([], roots) do
    roots
    |> Enum.flat_map(&Path.wildcard(Path.join(&1, "**/*_without_repo_test.exs")))
    |> normalize_files()
    |> ensure_nonempty!()
  end

  defp selected_files!(files, _roots) do
    files
    |> Enum.map(fn file ->
      unless String.ends_with?(file, ".exs") and File.regular?(file) do
        Mix.raise("test file must be an existing .exs file: #{inspect(file)}")
      end

      canonical_path(file)
    end)
    |> Enum.uniq()
    |> Enum.sort()
    |> ensure_nonempty!()
  end

  defp normalize_files(files),
    do: files |> Enum.map(&canonical_path/1) |> Enum.uniq() |> Enum.sort()

  defp canonical_path(path) do
    path
    |> Path.expand()
    |> Path.split()
    |> Enum.reduce("", fn
      "/", _current -> "/"
      component, current -> resolve_component(component, current)
    end)
  end

  defp resolve_component(component, current) do
    candidate = Path.join(current, component)

    case :file.read_link(String.to_charlist(candidate)) do
      {:ok, target} ->
        target = List.to_string(target)

        target =
          if Path.type(target) == :absolute,
            do: target,
            else: Path.join(Path.dirname(candidate), target)

        Path.expand(target)

      {:error, _reason} ->
        candidate
    end
  end

  defp ensure_nonempty!([]), do: Mix.raise("no without-repo test files were selected")
  defp ensure_nonempty!(files), do: files

  defp participating_roots(files, roots) do
    roots
    |> Enum.filter(fn root ->
      Enum.any?(files, fn file -> assigned_root(file, roots) == root end)
    end)
  end

  defp assigned_root(file, roots) do
    roots
    |> Enum.filter(&within_root?(file, &1))
    |> Enum.max_by(&String.length/1, fn -> nil end)
  end

  defp within_root?(file, root) do
    relative = Path.relative_to(file, root)
    Path.split(relative) |> List.first() != ".." and relative != file
  end

  defp load_helper(root) do
    helper = Path.join(root, "without_repo_helper.exs")
    if File.regular?(helper), do: Code.require_file(helper)
  end

  defp ensure_tests_ran!(%{total: total, skipped: skipped, excluded: excluded})
       when total > skipped + excluded,
       do: :ok

  defp ensure_tests_ran!(_result), do: Mix.raise("the selected files ran no non-skipped tests")
end
