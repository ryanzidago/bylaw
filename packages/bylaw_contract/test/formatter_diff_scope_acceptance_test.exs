defmodule Bylaw.Contract.FormatterDiffScopeAcceptanceTest do
  use ExUnit.Case, async: true, group: :contract_formatter
  alias Bylaw.Contract.TestFixtures.FormatterDiff

  setup do
    root = FormatterDiff.create()
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "unset diff scope runs one ordinary suite and one full observer without requiring Git", %{
    root: root
  } do
    File.rm_rf!(Path.join(root, ".git"))
    {output, status} = FormatterDiff.run(root, [])
    assert status == 0, output
    assert output =~ "functions=2"
    assert length(Regex.scan(~r/AUDIT_BODY/, output)) == 1
    assert output =~ "AUDIT_OBSERVERS=1"
    assert output =~ "AUDIT_STOPPED=0"
  end

  test "environment diff scope observes exactly the changed functions in one suite", %{root: root} do
    {output, status} = FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"}])
    assert status == 0, output
    assert output =~ "functions=1"
    assert length(Regex.scan(~r/AUDIT_BODY/, output)) == 1
    assert output =~ "AUDIT_OBSERVERS=1"
    assert output =~ "AUDIT_STOPPED=0"
  end

  test "explicit diff base overrides the environment and false restores full scope", %{root: root} do
    for {option, expected} <- [{"HEAD~1", "functions=1"}, {false, "functions=2"}] do
      {output, status} =
        FormatterDiff.run(root, [diff_base: option], [
          {"BYLAW_CONTRACT_DIFF_BASE", "invalid-reference"}
        ])

      assert status == 0, output
      assert output =~ expected
      assert output =~ "AUDIT_STOPPED=0"
    end
  end

  test "empty diff selection runs the suite with no check workers and an explicit diagnostic", %{
    root: root
  } do
    for report <- ["summary", nil] do
      {output, status} =
        FormatterDiff.run(root, [diff_base: "HEAD"], [{"BYLAW_CONTRACT_REPORT", report}])

      assert status == 0, output

      assert Enum.count(Regex.scan(~r/No functions selected for contract observation\./, output)) ==
               1

      if report == "summary", do: assert(output =~ "functions=0")
      assert output =~ "AUDIT_BODY"
      assert output =~ "AUDIT_STOPPED=0"
    end
  end

  test "invalid diff refs fail the process while ordinary tests still run", %{root: root} do
    {output, status} =
      FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", "missing-reference"}],
        before_start:
          ~S|System.at_exit(fn status -> IO.puts("AUDIT_EXIT_STATUS=" <> Integer.to_string(status)) end)|
      )

    assert status == 2, output
    assert output =~ "AUDIT_BODY"
    assert output =~ "AUDIT_OBSERVERS=0"
    assert output =~ "AUDIT_STOPPED=0"
    assert output =~ "Bylaw.Contract"
    assert output =~ "AUDIT_EXIT_STATUS=2"
    refute output =~ "Bylaw.Contract QA: functions="
  end

  test "dirty declared sources fail instead of silently selecting committed code", %{root: root} do
    path = Path.join(root, "lib/fixture.ex")
    File.write!(path, "# dirty source\n" <> File.read!(path))
    {output, status} = FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"}])
    assert status == 2, output
    assert output =~ "dirty_source"
    assert output =~ "AUDIT_BODY"
    assert output =~ "AUDIT_STOPPED=0"
  end

  test "original test failure status takes precedence over scope failure", %{root: root} do
    {output, status} =
      FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", "missing-reference"}],
        exit_status: 7,
        test_body: "assert false, \"original test failure\""
      )

    assert status == 7, output
    assert output =~ "original test failure"
    assert output =~ "AUDIT_OBSERVERS=0"
    assert output =~ "AUDIT_STOPPED=0"
  end

  test "incomplete scoped observation fails the process and releases its observer", %{root: root} do
    body = """
    [tracer] = Enum.filter(Process.list(), fn pid ->
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} -> Keyword.get(dict, :"$initial_call") == {Bylaw.Contract.Tracer, :init, 1}
        _ -> false
      end
    end)
    [worker] = :sys.get_state(tracer).workers
    try do
      :sys.suspend(worker)
      for _ <- 1..100, do: FormatterFixture.selected(1)
      Process.sleep(40)
    after
      if Process.alive?(worker), do: :sys.resume(worker)
    end
    """

    {output, status} =
      FormatterDiff.run(root, [max_trace_queue: 8], [{"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"}],
        test_body: body
      )

    assert status == 2, output
    assert output =~ "incomplete"
    assert output =~ "AUDIT_STOPPED=0"
    refute output =~ "Bylaw.Contract QA: functions="
  end

  test "malformed formatter options with enabled diff scope fail without suppressing the suite",
       %{root: root} do
    for options <- [[:invalid], :invalid] do
      {output, status} =
        FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"}],
          observation_options: options
        )

      assert status == 2, output
      assert output =~ "keyword list"
      assert output =~ "AUDIT_BODY"
      assert output =~ "AUDIT_OBSERVERS=0"
      assert output =~ "AUDIT_STOPPED=0"
    end
  end
end
