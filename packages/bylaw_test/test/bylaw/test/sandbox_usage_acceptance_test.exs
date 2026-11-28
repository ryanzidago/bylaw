defmodule Bylaw.Test.SandboxUsageAcceptanceTest do
  use ExUnit.Case, async: false

  alias Bylaw.Test.SandboxUsage
  alias Bylaw.Test.SandboxUsage.Formatter

  @package_path Path.expand("../../..", __DIR__)
  @event [:bylaw_test, :repo, :query]

  test "passing watched test with zero queries produces a violation and fails check!" do
    {server, formatter} = start_isolated_tracker()

    module = UnusedSandboxModule
    test_name = :"test runs no queries"
    file = "test/unused_sandbox_test.exs"
    line = 42

    SandboxUsage.watch(
      %{module: module, test: test_name, file: file, line: line, async: true},
      server: server
    )

    GenServer.cast(
      formatter,
      {:test_finished, %ExUnit.Test{case: module, name: test_name, state: nil}}
    )

    _ = :sys.get_state(formatter)

    assert [violation] = SandboxUsage.violations(server: server)
    assert violation.module == module
    assert violation.test == test_name
    assert violation.file == file
    assert violation.line == line

    error =
      assert_raise ExUnit.AssertionError, fn ->
        SandboxUsage.check!(%{total: 1, failures: 0}, server: server)
      end

    assert error.message =~ "#{file}:#{line}"
    assert error.message =~ inspect(module)
    assert error.message =~ inspect(test_name)
    assert error.message =~ "ExUnit.Case"
  end

  test "direct query or Task.async child query satisfies the check" do
    {server, formatter} = start_isolated_tracker()

    SandboxUsage.watch(
      %{module: DirectQueryCase, test: :"test direct", file: "a.exs", line: 10, async: true},
      server: server
    )

    :telemetry.execute(@event, %{}, %{query: "SELECT 1"})

    GenServer.cast(
      formatter,
      {:test_finished, %ExUnit.Test{case: DirectQueryCase, name: :"test direct", state: nil}}
    )

    SandboxUsage.watch(
      %{module: CallerQueryCase, test: :"test task", file: "b.exs", line: 20, async: true},
      server: server
    )

    Task.async(fn ->
      :telemetry.execute(@event, %{}, %{query: "INSERT INTO items VALUES ($1)"})
    end)
    |> Task.await()

    GenServer.cast(
      formatter,
      {:test_finished, %ExUnit.Test{case: CallerQueryCase, name: :"test task", state: nil}}
    )

    _ = :sys.get_state(formatter)

    assert SandboxUsage.violations(server: server) == []
    assert :ok == SandboxUsage.check!(%{total: 2, failures: 0}, server: server)
  end

  test "built-in SQL plumbing and custom ignore matchers do not count as real queries" do
    {server, formatter} =
      start_isolated_tracker(
        ignore: [
          ~r/\bset_config\('application_name'/i,
          fn query -> String.starts_with?(query, "-- ignore") end
        ]
      )

    module = PlumbingOnlyCase
    test_name = :"test only plumbing"

    SandboxUsage.watch(
      %{module: module, test: test_name, file: "plumbing_test.exs", line: 7, async: true},
      server: server
    )

    for sql <- [
          "BEGIN",
          "SAVEPOINT ecto_sandbox",
          "RELEASE SAVEPOINT ecto_sandbox",
          "ROLLBACK TO SAVEPOINT ecto_sandbox",
          "COMMIT",
          "ROLLBACK",
          "SELECT set_config('application_name', $1, false)",
          "-- ignore setup"
        ] do
      :telemetry.execute(@event, %{}, %{query: sql})
    end

    GenServer.cast(
      formatter,
      {:test_finished, %ExUnit.Test{case: module, name: test_name, state: nil}}
    )

    _ = :sys.get_state(formatter)

    assert [%{module: ^module, test: ^test_name}] = SandboxUsage.violations(server: server)
  end

  test "failing or skipped tests do not produce unused-sandbox violations" do
    {server, formatter} = start_isolated_tracker()

    for {mod, name, state} <- [
          {FailingCase, :"test fails", {:failed, []}},
          {SkippedCase, :"test skips", {:skipped, "skipped"}}
        ] do
      SandboxUsage.watch(
        %{module: mod, test: name, file: "skip_or_fail_test.exs", line: 12, async: true},
        server: server
      )

      GenServer.cast(
        formatter,
        {:test_finished, %ExUnit.Test{case: mod, name: name, state: state}}
      )
    end

    _ = :sys.get_state(formatter)

    assert SandboxUsage.violations(server: server) == []
  end

  test "shared mode credits queries from unrelated processes while async mode does not" do
    {server, formatter} = start_isolated_tracker()

    SandboxUsage.watch(
      %{module: AsyncCase, test: :"test async", file: "async_test.exs", line: 5, async: true},
      server: server
    )

    emit_unlinked_query()

    GenServer.cast(
      formatter,
      {:test_finished, %ExUnit.Test{case: AsyncCase, name: :"test async", state: nil}}
    )

    _ = :sys.get_state(formatter)

    assert [%{module: AsyncCase}] = SandboxUsage.violations(server: server)

    {server2, formatter2} = start_isolated_tracker()

    SandboxUsage.watch(
      %{module: SharedCase, test: :"test shared", file: "shared_test.exs", line: 8, async: false},
      server: server2
    )

    emit_unlinked_query()

    GenServer.cast(
      formatter2,
      {:test_finished, %ExUnit.Test{case: SharedCase, name: :"test shared", state: nil}}
    )

    _ = :sys.get_state(formatter2)

    assert SandboxUsage.violations(server: server2) == []
  end

  test "end-to-end mix test fails on zero-query watched test and passes when queried or unwatched" do
    root =
      Path.join(
        System.tmp_dir!(),
        "bylaw_sandbox_usage-#{:os.getpid()}-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf!(root) end)

    project = Path.join(root, "consumer")
    File.mkdir_p!(Path.join(project, "test/support"))
    File.ln_s!(Path.join(@package_path, "deps"), Path.join(project, "deps"))
    File.cp!(Path.join(@package_path, "mix.lock"), Path.join(project, "mix.lock"))

    File.write!(Path.join(project, "mix.exs"), """
    defmodule Consumer.MixProject do
      use Mix.Project

      def project do
        [
          app: :consumer,
          version: "0.1.0",
          elixir: "~> 1.19",
          elixirc_paths: ["lib", "test/support"],
          deps: [{:bylaw_test, path: #{inspect(@package_path)}, only: :test}]
        ]
      end

      def application, do: [extra_applications: [:logger]]
    end
    """)

    File.mkdir_p!(Path.join(project, "lib"))
    File.write!(Path.join(project, "lib/consumer.ex"), "defmodule Consumer, do: nil\n")

    File.write!(Path.join(project, "test/support/data_case.ex"), """
    defmodule Consumer.DataCase do
      use ExUnit.CaseTemplate

      setup tags do
        Bylaw.Test.SandboxUsage.watch(tags)
        :ok
      end
    end
    """)

    File.write!(Path.join(project, "test/test_helper.exs"), """
    {:ok, _} =
      Bylaw.Test.SandboxUsage.start_link(
        events: [[:consumer, :repo, :query]],
        ignore: [~r/\\bset_config\\('application_name'/i]
      )

    ExUnit.start(formatters: [ExUnit.CLIFormatter, Bylaw.Test.SandboxUsage.Formatter])
    ExUnit.after_suite(&Bylaw.Test.SandboxUsage.check!/1)
    """)

    test_file = Path.join(project, "test/sample_test.exs")

    File.write!(test_file, """
    defmodule Consumer.SampleTest do
      use Consumer.DataCase, async: true

      test "checked out sandbox with no queries" do
        assert 1 + 1 == 2
      end
    end
    """)

    {output, status} =
      System.cmd("mix", ["test"], cd: project, env: [{"MIX_ENV", "test"}], stderr_to_stdout: true)

    assert status != 0
    assert output =~ "Consumer.SampleTest"
    assert output =~ "ExUnit.Case"

    File.write!(test_file, """
    defmodule Consumer.SampleTest do
      use ExUnit.Case, async: true

      test "pure test in ExUnit.Case" do
        assert 1 + 1 == 2
      end
    end

    defmodule Consumer.DbTest do
      use Consumer.DataCase, async: true

      test "runs a real query" do
        :telemetry.execute([:consumer, :repo, :query], %{}, %{query: "SELECT 1"})
        assert true
      end
    end
    """)

    {output, status} =
      System.cmd("mix", ["test"], cd: project, env: [{"MIX_ENV", "test"}], stderr_to_stdout: true)

    assert status == 0, output
  end

  defp start_isolated_tracker(opts \\ []) do
    name = :"sandbox_usage_#{System.unique_integer([:positive])}"
    start_opts = Keyword.merge([events: [@event], name: name], opts)
    tracker_spec = Supervisor.child_spec({SandboxUsage, start_opts}, id: {:tracker, name})
    {:ok, _pid} = start_supervised(tracker_spec)

    formatter_spec = %{
      id: {:formatter, name},
      start: {GenServer, :start_link, [Formatter, [bylaw_test: [server: name]]]}
    }

    {:ok, formatter} = start_supervised(formatter_spec)
    {name, formatter}
  end

  defp emit_unlinked_query do
    parent = self()

    spawn(fn ->
      :telemetry.execute(@event, %{}, %{query: "SELECT 42"})
      send(parent, :queried)
    end)

    assert_receive :queried
  end
end
