defmodule Bylaw.Contract.PreparationOverlapAcceptanceTest do
  use ExUnit.Case, async: true, group: :contract_qa_fixture

  @tag :tmp_dir
  test "serialized loading waits for successful preparation and retains measured boundaries",
       context do
    {audit, _capture, 0} = run(context, "serialized")
    ready = event(audit, "prepared")
    loading = event(audit, "require_started")
    assert ready["at_us"] <= loading["at_us"]
    assert loading["details"]["files"] == 12
    assert loading["details"]["max_requires"] == 4
    assert audit["cleanup"]["clean"]
  end

  @tag :tmp_dir
  test "normal and serialized preparation preserve exact fixture coverage and native tests",
       context do
    {_, first, 0} = run(context, "normal")
    {_, second, 0} = run(context, "serialized")
    assert first.coverage == second.coverage
    assert is_binary(first.report_sha256)
    assert first.report_sha256 == second.report_sha256
    assert first.test_states == %{passed: 12}
    assert second.test_states == first.test_states
    assert Enum.sort(first.test_identities) == Enum.sort(second.test_identities)

    for capture <- [first, second] do
      assert capture.compiler_options == %{
               docs: false,
               debug_info: false,
               infer_signatures: false
             }

      assert map_size(capture.coverage.calls) == 12
      assert Enum.all?(capture.coverage.calls, fn {_, count} -> count == 20 end)
      assert Enum.all?(capture.coverage.arity_calls, fn {_, count} -> count == 20 end)
    end
  end

  @tag :tmp_dir
  test "preparation before loading retains the first setup and test calls", context do
    for layout <- ["normal", "serialized"] do
      {_, capture, 0} = run(context, layout, "setup")
      mfa = {BylawPhaseFixture.Classifier1, :classify, 1}
      assert capture.coverage.calls[mfa] == 21
      assert capture.coverage.return_events[mfa] == 21
      assert capture.coverage.arity_calls[mfa] == 21
    end
  end

  @tag :tmp_dir
  test "startup and test loading failures release prepared workers tracing and shadow code",
       context do
    for layout <- ["normal", "serialized"], scenario <- ["init_failure", "load_failure"] do
      {audit, _, status} = run(context, layout, scenario)
      assert status != 0
      assert audit["cleanup"]["clean"]
      assert Enum.empty?(audit["cleanup"]["shadows"])

      if scenario == "init_failure" do
        assert event(audit, "failure_check_reached")["details"]["shadow_count"] == 1
      else
        if layout == "serialized" do
          assert event(audit, "prepared")["details"]["workers"] == 2
        else
          assert event(audit, "require_started")["details"]["files"] == 13
        end
      end
    end
  end

  @tag :tmp_dir
  test "serialized preparation coexists with native line coverage", context do
    {audit, capture, 0} = run(context, "serialized", "cover")
    assert audit["cleanup"]["clean"]
    assert capture.test_states == %{passed: 12}
    assert Enum.all?(capture.coverage.calls, fn {_, count} -> count == 20 end)
  end

  defp run(context, layout, scenario \\ "normal") do
    on_exit(fn -> File.rm_rf!(context.tmp_dir) end)
    directory = Path.join(context.tmp_dir, "project-" <> scenario)
    File.mkdir_p!(directory)

    for path <- ["lib", "test", "mix.exs"] do
      File.cp_r!(Path.join("qa/performance_phase_fixture", path), Path.join(directory, path))
    end

    if scenario == "setup" do
      path = Path.join(directory, "test/classifier_1_test.exs")
      text = File.read!(path)
      setup = "  setup do\n    BylawPhaseFixture.Classifier1.classify(1)\n    :ok\n  end\n\n"
      File.write!(path, String.replace(text, "  test ", setup <> "  test ", global: false))
    end

    if scenario == "load_failure" do
      File.write!(
        Path.join(directory, "test/broken_test.exs"),
        "raise \"retained loading failure\"\n"
      )
    end

    capture_path = Path.join(directory, layout <> "-capture.etf")
    audit_path = Path.join(directory, layout <> "-audit.json")

    args = [
      "-pa",
      Application.app_dir(:bylaw_contract, "ebin"),
      "-r",
      Path.expand("qa/preparation-overlap.exs"),
      "-S",
      "mix",
      "test",
      "--seed",
      "922331",
      "--max-requires",
      "4",
      "--max-cases",
      "4",
      "--formatter",
      "ExUnit.CLIFormatter",
      "--formatter",
      "BylawPreparationCapture"
    ]

    args = if scenario == "cover", do: args ++ ["--cover"], else: args

    {log, status} =
      System.cmd(
        "python3",
        [
          "-c",
          ~S"""
          import os,signal,subprocess,sys
          child=subprocess.Popen(sys.argv[1:],start_new_session=True)
          try:
              code=child.wait(timeout=25)
          except subprocess.TimeoutExpired:
              os.killpg(child.pid,signal.SIGKILL)
              child.wait()
              print("preparation acceptance child exceeded 25s deadline",file=sys.stderr)
              code=124
          sys.exit(code)
          """,
          "elixir" | args
        ],
        cd: directory,
        stderr_to_stdout: true,
        env: [
          {"BYLAW_PREPARATION_LAYOUT", layout},
          {"BYLAW_PREPARATION_SCENARIO", scenario},
          {"BYLAW_PREPARATION_OUTPUT", audit_path},
          {"BYLAW_OVERHEAD_OUTPUT", capture_path},
          {"BYLAW_OVERHEAD_EBIN", Application.app_dir(:bylaw_contract, "ebin")},
          {"BYLAW_CONTRACT_APPS", "bylaw_phase_fixture"},
          {"MIX_ENV", "test"}
        ]
      )

    assert File.regular?(audit_path), log
    audit = audit_path |> File.read!() |> JSON.decode!()

    capture =
      if File.regular?(capture_path), do: capture_path |> File.read!() |> :erlang.binary_to_term()

    {audit, capture, status}
  end

  defp event(audit, name), do: Enum.find(audit["events"], &(&1["name"] == name))
end
