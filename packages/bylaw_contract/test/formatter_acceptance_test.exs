defmodule Bylaw.Contract.FormatterAcceptanceTest do
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias Bylaw.Contract.ExUnitFormatter
  alias Bylaw.Contract.Fixtures.Countdown
  alias Bylaw.Contract.Fixtures.Greeter

  test "instruments the configured modules when the suite starts and prints the report when it ends" do
    output =
      capture_io(fn ->
        {:ok, formatter} =
          GenServer.start_link(ExUnitFormatter, bylaw_contract: [modules: [Greeter]])

        Greeter.greet(:admin)
        GenServer.cast(formatter, {:suite_finished, %{run: 0, async: 0, load: nil}})
        :sys.get_state(formatter)
      end)

    assert output =~ "Bylaw.Contract.Fixtures.Greeter.greet/1"
    assert output =~ "Untested clause"
  end

  test "prints a one line warning count instead of every warning" do
    output =
      capture_io(fn ->
        {:ok, formatter} =
          GenServer.start_link(ExUnitFormatter, bylaw_contract: [modules: [Countdown, Greeter]])

        GenServer.cast(formatter, {:suite_finished, %{run: 0, async: 0, load: nil}})
        :sys.get_state(formatter)
      end)

    assert output =~ "Bylaw.Contract: 1 warning"
    refute output =~ "recursive"
  end

  test "prints every warning when the warnings option is set" do
    output =
      capture_io(fn ->
        {:ok, formatter} =
          GenServer.start_link(ExUnitFormatter,
            bylaw_contract: [modules: [Countdown], warnings: true]
          )

        GenServer.cast(formatter, {:suite_finished, %{run: 0, async: 0, load: nil}})
        :sys.get_state(formatter)
      end)

    assert output =~ "count_down/1 is recursive"
  end

  test "restores the instrumented modules after the suite ends" do
    original = {Greeter.module_info(:md5), :code.which(Greeter)}

    capture_io(fn ->
      {:ok, formatter} =
        GenServer.start_link(ExUnitFormatter, bylaw_contract: [modules: [Greeter]])

      GenServer.cast(formatter, {:suite_finished, %{run: 0, async: 0, load: nil}})
      :sys.get_state(formatter)
    end)

    assert {Greeter.module_info(:md5), :code.which(Greeter)} == original
  end

  test "never observes test support modules or the observer's own runtime modules by default" do
    assert ExUnitFormatter.default_modules() == []
  end

  test "says that findings reflect only the tests that ran when tests were excluded, skipped or failed" do
    output =
      capture_io(fn ->
        {:ok, formatter} =
          GenServer.start_link(ExUnitFormatter, bylaw_contract: [modules: [Greeter]])

        for state <- [
              {:excluded, "due to slow filter"},
              {:excluded, "due to slow filter"},
              {:skipped, "later"},
              {:failed, []},
              nil
            ] do
          GenServer.cast(formatter, {:test_finished, %ExUnit.Test{state: state}})
        end

        GenServer.cast(formatter, {:suite_finished, %{run: 0, async: 0, load: nil}})
        :sys.get_state(formatter)
      end)

    assert output =~ "reflect only the tests that ran: 3 excluded or skipped, 1 failed"
  end

  test "prints no test-run note when every test ran and passed" do
    output =
      capture_io(fn ->
        {:ok, formatter} =
          GenServer.start_link(ExUnitFormatter, bylaw_contract: [modules: [Greeter]])

        GenServer.cast(formatter, {:test_finished, %ExUnit.Test{state: nil}})
        GenServer.cast(formatter, {:suite_finished, %{run: 0, async: 0, load: nil}})
        :sys.get_state(formatter)
      end)

    refute output =~ "reflect only"
  end

  test "reports only functions changed since the revision given by the since option" do
    repository = Path.join(System.tmp_dir!(), "bylaw-since-#{System.unique_integer([:positive])}")
    File.mkdir_p!(repository)
    on_exit(fn -> File.rm_rf!(repository) end)

    git = fn arguments ->
      System.cmd("git", ["-c", "core.hooksPath=/dev/null" | arguments],
        cd: repository,
        stderr_to_stdout: true,
        env: [{"GIT_DIR", nil}, {"GIT_WORK_TREE", nil}, {"GIT_INDEX_FILE", nil}]
      )
    end

    git.(["init", "-q"])

    git.([
      "-c",
      "user.name=t",
      "-c",
      "user.email=t@t",
      "commit",
      "-q",
      "--allow-empty",
      "-m",
      "x"
    ])

    output =
      in_directory(repository, fn ->
        capture_io(fn ->
          {:ok, formatter} =
            GenServer.start_link(ExUnitFormatter,
              bylaw_contract: [modules: [Greeter], since: "HEAD"]
            )

          GenServer.cast(formatter, {:suite_finished, %{run: 0, async: 0, load: nil}})
          :sys.get_state(formatter)
        end)
      end)

    refute output =~ "Greeter.greet/1"
  end

  test "hides baselined findings, counts them, and rewrites the baseline on request" do
    baseline = Path.join(System.tmp_dir!(), "bylaw-fmt-#{System.unique_integer([:positive])}.txt")
    on_exit(fn -> File.rm(baseline) end)

    run = fn ->
      capture_io(fn ->
        {:ok, formatter} =
          GenServer.start_link(ExUnitFormatter,
            bylaw_contract: [modules: [Greeter], baseline: baseline]
          )

        Greeter.greet(:admin)
        GenServer.cast(formatter, {:suite_finished, %{run: 0, async: 0, load: nil}})
        :sys.get_state(formatter)
      end)
    end

    System.put_env("BYLAW_CONTRACT_UPDATE_BASELINE", "1")
    written = run.()
    System.delete_env("BYLAW_CONTRACT_UPDATE_BASELINE")

    assert written =~ "wrote"
    assert File.read!(baseline) =~ "Bylaw.Contract.Fixtures.Greeter.greet/1|clause|2"

    hidden = run.()

    refute hidden =~ "Untested clause"
    assert hidden =~ "findings hidden by the baseline"
  end

  defp in_directory(directory, fun) do
    original = File.cwd!()
    File.cd!(directory)

    try do
      fun.()
    after
      File.cd!(original)
    end
  end
end
