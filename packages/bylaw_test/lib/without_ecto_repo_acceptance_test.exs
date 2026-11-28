defmodule Bylaw.Test.WithoutEctoRepoAcceptanceTest do
  use ExUnit.Case, async: false

  @package_path Path.expand("..", __DIR__)

  test "discovers lib and test roots, runs case templates, and leaves the app stopped" do
    root = isolated_root()
    project = downstream_project(root, ["lib", "test"])
    marker = Path.join(root, "loaded")
    File.write!(Path.join(project, "lib/without_repo_helper.exs"), marker_source(marker, "lib"))
    File.write!(Path.join(project, "test/without_repo_helper.exs"), marker_source(marker, "test"))

    File.write!(
      Path.join(project, "test/test_helper.exs"),
      "raise \"ordinary helper was loaded\"\n"
    )

    File.write!(Path.join(project, "lib/case_templates.ex"), case_templates_source())

    File.write!(
      Path.join(project, "lib/alpha_without_repo_test.exs"),
      template_test_source("Fixture.SelectedRepoCase", "alpha", marker)
    )

    File.write!(
      Path.join(project, "test/beta_without_repo_test.exs"),
      template_test_source("Fixture.OtherRepoCase", "beta", marker)
    )

    File.write!(Path.join(project, "test/ordinary_test.exs"), "raise \"ordinary test loaded\"\n")

    {_output, 0} = run_task(project)

    assert File.read!(marker) |> String.split("\n", trim: true) |> Enum.take(2) == ["lib", "test"]
    assert File.read!(marker) =~ "alpha"
    assert File.read!(marker) =~ "beta"
  end

  test "explicit files replace discovery, deduplicate, and load only the most specific root helper" do
    root = isolated_root()
    project = downstream_project(root, ["test", "test", "test/nested"])
    marker = Path.join(root, "loaded")
    File.write!(Path.join(project, "test/without_repo_helper.exs"), marker_source(marker, "root"))

    File.write!(
      Path.join(project, "test/nested/without_repo_helper.exs"),
      marker_source(marker, "nested")
    )

    nested = Path.join(project, "test/nested/selected.exs")
    outside = Path.join(root, "outside.exs")
    File.write!(nested, consumer_test_source(marker, "nested-test"))
    File.write!(outside, consumer_test_source(marker, "outside-test"))

    File.write!(
      Path.join(project, "test/default_without_repo_test.exs"),
      "raise \"discovery was not replaced\"\n"
    )

    {_output, 0} = run_task(project, [nested, nested, outside])

    assert File.read!(marker) |> String.split("\n", trim: true) |> Enum.take(1) == ["nested"]
    assert Enum.count(String.split(File.read!(marker), "\n"), &(&1 == "nested-test")) == 1
    assert File.read!(marker) =~ "nested-test"
    assert File.read!(marker) =~ "outside-test"
    refute File.read!(marker) =~ "root"
  end

  test "repo options replace configured defaults and require_repo! is scoped to the active run" do
    root = isolated_root()
    project = downstream_project(root, ["test"])
    test_file = Path.join(project, "test/explicit.exs")

    File.write!(test_file, """
    defmodule Fixture.RepoSelectionTest do
      use ExUnit.Case
      test "selected repo assertion is scoped" do
        assert :ok == Bylaw.Test.require_repo!(Fixture.Repo, %{case: __MODULE__})
        error = assert_raise ExUnit.AssertionError, fn ->
          Bylaw.Test.require_repo!(Fixture.OtherRepo, %{case: __MODULE__})
        end
        assert error.message =~ inspect(__MODULE__)
        assert_raise ExUnit.AssertionError, fn ->
          Bylaw.Test.require_repo!(Fixture.AnotherRepo, %{case: __MODULE__})
        end
      end
    end
    """)

    {_output, 0} =
      run_task(project, [
        "--repo",
        "Fixture.OtherRepo",
        "--repo",
        "Fixture.AnotherRepo",
        test_file
      ])
  end

  test "rejects invalid inputs, empty and skipped-only runs, and test failures" do
    root = isolated_root()
    project = downstream_project(root, ["test"])
    file = Path.join(project, "test/explicit.exs")

    File.write!(
      file,
      "defmodule Fixture.Pass do\n use ExUnit.Case\n test \"pass\", do: assert(true)\nend\n"
    )

    assert {_, 0} = run_task(project, [file])
    assert {output, 1} = run_task(project, ["--unknown"])
    assert output =~ "invalid arguments"
    assert {output, 1} = run_task(project, [Path.join(project, "test/missing.exs")])
    assert output =~ "existing .exs file"
    assert {output, 1} = run_task(project, ["--repo", "Fixture..Repo", file])
    assert output =~ "invalid repo module name"
    assert {output, 1} = run_task(project, ["--repo", "Fixture.MissingRepo", file])
    assert output =~ "not a loaded Ecto repo module"

    File.rm!(file)
    assert {output, 1} = run_task(project)
    assert output =~ "no without-repo test files"

    File.write!(file, "\n")
    assert {output, 1} = run_task(project, [file])
    assert output =~ "no non-skipped tests"

    File.write!(
      file,
      "defmodule Fixture.Skipped do\n use ExUnit.Case\n @tag :skip\n test \"skip\", do: flunk()\nend\n"
    )

    assert {output, 1} = run_task(project, [file])
    assert output =~ "no non-skipped tests"

    File.write!(
      file,
      "defmodule Fixture.Failure do\n use ExUnit.Case\n test \"failure\", do: flunk()\nend\n"
    )

    assert {output, 1} = run_task(project, [file])
    assert output =~ "1 of 1 tests failed"

    File.write!(
      Path.join(project, "config/config.exs"),
      "import Config\nconfig :fixture, ecto_repos: []\n"
    )

    assert {output, 1} = run_task(project, [file])
    assert output =~ "configure at least one repo"
  end

  test "repo modules and the consumer app are checked before and after helpers and tests" do
    root = isolated_root()
    project = downstream_project(root, ["test"])
    helper = Path.join(project, "test/without_repo_helper.exs")
    file = Path.join(project, "test/explicit.exs")

    File.write!(
      file,
      "defmodule Fixture.Check do\n use ExUnit.Case\n test \"pass\", do: assert(true)\nend\n"
    )

    File.write!(helper, "Process.register(self(), Fixture.Repo)\n")
    assert {output, 1} = run_task(project, [file])
    assert output =~ "Fixture.Repo is started"

    File.rm!(helper)

    File.write!(file, """
    defmodule Fixture.StartRepo do
      use ExUnit.Case
      test "starts selected repo" do
        parent = self()
        spawn(fn ->
          Process.register(self(), Fixture.Repo)
          send(parent, :registered)
          receive do :stop -> :ok end
        end)
        assert_receive :registered
      end
    end
    """)

    assert {output, 1} = run_task(project, [file])
    assert output =~ "Fixture.Repo is started"

    File.write!(helper, "{:ok, _} = Application.ensure_all_started(:fixture)\n")

    File.write!(file, """
    defmodule Fixture.AppWithReposDisabled do
      use ExUnit.Case
      test "project startup is allowed while selected repos remain stopped" do
        assert :fixture in Enum.map(Application.started_applications(), &elem(&1, 0))
        refute Process.whereis(Fixture.Repo)
      end
    end
    """)

    assert {_, 0} = run_task(project, [file])
  end

  test "require_repo! is a no-op in ordinary ExUnit tests" do
    assert :ok == Bylaw.Test.require_repo!(Fixture.Repo, %{case: __MODULE__})
  end

  test "uses Mix's default test root when test_paths is not configured" do
    root = isolated_root()
    project = downstream_project(root, ["test"])
    mix_file = Path.join(project, "mix.exs")
    mix_source = File.read!(mix_file)
    File.write!(mix_file, String.replace(mix_source, ", test_paths: [\"test\"],", ","))
    marker = Path.join(root, "default-root")

    File.write!(
      Path.join(project, "test/default_without_repo_test.exs"),
      consumer_test_source(marker, "default")
    )

    {_output, 0} = run_task(project)
    assert File.read!(marker) == "default\n"
  end

  defp downstream_project(root, test_paths) do
    project = Path.join(root, "consumer")
    File.mkdir_p!(Path.join(project, "lib"))
    File.mkdir_p!(Path.join(project, "config"))
    Enum.each(test_paths, &File.mkdir_p!(Path.join(project, &1)))

    File.write!(Path.join(project, "mix.exs"), """
    defmodule Fixture.MixProject do
      use Mix.Project
      def project do
        [app: :fixture, version: "0.1.0", elixir: "~> 1.19", test_paths: #{inspect(test_paths)},
         deps: [{:bylaw_test, path: #{@package_path |> inspect()}, only: :test, runtime: false}]]
      end
      def application, do: [mod: {Fixture.Application, []}, extra_applications: [:logger]]
    end
    """)

    File.write!(Path.join(project, "config/config.exs"), """
    import Config
    config :fixture, ecto_repos: [Fixture.Repo]
    """)

    File.write!(Path.join(project, "lib/repo.ex"), """
    defmodule Fixture.Repo do
      def __adapter__, do: Fixture.Adapter
    end
    defmodule Fixture.OtherRepo do
      def __adapter__, do: Fixture.Adapter
    end
    defmodule Fixture.AnotherRepo do
      def __adapter__, do: Fixture.Adapter
    end
    defmodule Fixture.Application do
      use Application
      def start(_type, _args) do
        Supervisor.start_link([], strategy: :one_for_one)
      end
    end
    """)

    project
  end

  defp isolated_root do
    root =
      Path.join(
        System.tmp_dir!(),
        "bylaw_test-#{:os.getpid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    root
  end

  defp marker_source(path, value) do
    "File.write!(#{inspect(path)}, #{inspect(value <> "\n")}, [:append])\n"
  end

  defp consumer_test_source(marker, value) do
    """
    defmodule Fixture.#{Macro.camelize(String.replace(value, "-", "_"))}Test do
      use ExUnit.Case
      test "consumer test runs while application is stopped" do
        refute :fixture in Enum.map(Application.started_applications(), &elem(&1, 0))
        assert :ok == Bylaw.Test.require_repo!(Fixture.OtherRepo, %{case: __MODULE__})
        File.write!(#{inspect(marker)}, #{inspect(value <> "\n")}, [:append])
      end
    end
    """
  end

  defp case_templates_source do
    """
    defmodule Fixture.SelectedRepoCase do
      use ExUnit.CaseTemplate
      setup context do
        error = assert_raise ExUnit.AssertionError, fn ->
          Bylaw.Test.require_repo!(Fixture.Repo, context)
        end
        assert error.message =~ inspect(Fixture.Repo)
        assert error.message =~ inspect(Map.fetch!(context, :module))
        :ok
      end
    end
    defmodule Fixture.OtherRepoCase do
      use ExUnit.CaseTemplate
      setup context do
        assert :ok == Bylaw.Test.require_repo!(Fixture.OtherRepo, context)
        :ok
      end
    end
    """
  end

  defp template_test_source(template, name, marker) do
    """
    defmodule Fixture.#{Macro.camelize(name)}Test do
      use #{template}
      test "#{name} setup receives the test case" do
        assert __MODULE__ == __ENV__.module
        File.write!(#{inspect(marker)}, #{inspect(name <> "\n")}, [:append])
      end
    end
    """
  end

  defp run_task(project, args \\ []) do
    System.cmd("mix", ["bylaw_test.without_ecto_repo" | args],
      cd: project,
      env: [{"MIX_ENV", "test"}],
      stderr_to_stdout: true
    )
  end
end
