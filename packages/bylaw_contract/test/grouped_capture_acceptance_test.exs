defmodule Bylaw.Contract.GroupedCaptureAcceptanceTest do
  use ExUnit.Case, async: false

  @tag :tmp_dir
  test "suite captures preserve every test identity and terminal failure", context do
    {result, status} = run(context, "failure", "assert false, \"retained failure\"")
    assert status == 1
    assert length(result["tests"]) == 3
    assert Enum.count(result["tests"], &(&1["state"] == "failed")) == 1
    assert Enum.any?(result["tests"], &String.contains?(&1["failure"] || "", "retained failure"))

    assert Enum.sort(Enum.map(result["tests"], & &1["module"])) == [
             "Elixir.GroupedFixture.AlphaOne",
             "Elixir.GroupedFixture.AlphaTwo",
             "Elixir.GroupedFixture.Beta"
           ]

    assert result["cleanup"]["clean"]
  end

  @tag :tmp_dir
  test "suite captures distinguish overlapping groups from serialized group members", context do
    {result, 0} = run(context, "groups")
    cases = result["cases"]
    alpha = cases |> Enum.filter(&(&1["group"] == ":alpha")) |> Enum.sort_by(& &1["started_us"])
    [first, second] = alpha
    assert first["finished_us"] <= second["started_us"]
    beta = Enum.find(cases, &(&1["group"] == ":beta"))

    assert Enum.any?(alpha, fn member ->
             max(member["started_us"], beta["started_us"]) <
               min(member["finished_us"], beta["finished_us"])
           end)

    assert result["cleanup"]["clean"]
  end

  @tag :tmp_dir
  test "cleanup audits detect live contract resources and restored global settings", context do
    body = """
    {:ok, observer} = Bylaw.Contract.start([Bylaw.Contract.StructuralExample])
    Process.unlink(observer)
    System.put_env("BYLAW_CONTRACT_REPORT", "deliberately-leaked")
    """

    {result, 2} = run(context, "leak", body)
    refute result["cleanup"]["clean"]
    refute result["cleanup"]["environment_restored"]
    refute Enum.empty?(result["cleanup"]["workers"])
    refute Enum.empty?(result["cleanup"]["shadows"])
    refute Enum.empty?(result["cleanup"]["sessions"])
    assert Enum.all?(result["tests"], &(&1["state"] == "passed"))

    {restored, 0} = run(context, "restored")
    assert restored["cleanup"]["clean"]

    {git_leak, 2} = run(context, "git-environment", ~S|System.put_env("GIT_DIR", "/leaked-git")|)
    refute git_leak["cleanup"]["clean"]
    refute git_leak["cleanup"]["environment_restored"]
  end

  defp run(context, name, beta_body \\ "assert true") do
    on_exit(fn -> File.rm_rf!(context.tmp_dir) end)
    output = Path.join(context.tmp_dir, name <> ".json")

    source = """
    ExUnit.start(autorun: false, seed: 922331, max_cases: 2,
      formatters: [ExUnit.CLIFormatter, BylawGroupedSuiteCapture])
    {:ok, _} = Agent.start_link(fn -> MapSet.new() end, name: GroupedFixture.Barrier)
    defmodule GroupedFixture.BarrierWait do
      def wait(group) do
        Agent.update(GroupedFixture.Barrier, &MapSet.put(&1, group))
        await(1000)
      end
      defp await(0), do: raise("independent group never became runnable")
      defp await(left) do
        if Agent.get(GroupedFixture.Barrier, &MapSet.size/1) < 2 do
          Process.sleep(1)
          await(left - 1)
        end
      end
    end
    defmodule GroupedFixture.AlphaOne do
      use ExUnit.Case, async: true, group: :alpha
      test "first member" do
        GroupedFixture.BarrierWait.wait(:alpha)
        assert true
      end
    end
    defmodule GroupedFixture.AlphaTwo do
      use ExUnit.Case, async: true, group: :alpha
      test "second member" do
        GroupedFixture.BarrierWait.wait(:alpha)
        assert true
      end
    end
    defmodule GroupedFixture.Beta do
      use ExUnit.Case, async: true, group: :beta
      test "independent member" do
        GroupedFixture.BarrierWait.wait(:beta)
        #{beta_body}
      end
    end
    result = ExUnit.run()
    if result.failures > 0, do: System.at_exit(fn _ -> exit({:shutdown, 1}) end)
    """

    {log, status} =
      System.cmd(
        "elixir",
        [
          "-pa",
          Application.app_dir(:bylaw_contract, "ebin"),
          "-r",
          "qa/grouped-suite-capture.exs",
          "-e",
          source
        ],
        env: [{"BYLAW_GROUPED_OUTPUT", output}],
        stderr_to_stdout: true
      )

    assert File.exists?(output), log
    {output |> File.read!() |> JSON.decode!(), status}
  end
end
