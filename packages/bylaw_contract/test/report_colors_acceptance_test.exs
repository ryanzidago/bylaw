defmodule Bylaw.Contract.ReportColorsAcceptanceTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias Bylaw.Contract
  alias Bylaw.Contract.ExUnitFormatter

  defmodule FixtureCheck do
    @behaviour Bylaw.Contract.Check

    @impl Bylaw.Contract.Check
    def init(_, opts, _) do
      {:ok, Keyword.fetch!(opts, :coverage),
       %{calls: MapSet.new(), returns: MapSet.new(), claims: MapSet.new()}}
    end

    @impl Bylaw.Contract.Check
    def observe(_, state), do: state

    @impl Bylaw.Contract.Check
    def coverage(state), do: state

    @impl Bylaw.Contract.Check
    def terminate(_), do: :ok
  end

  setup do
    previous = Application.fetch_env(:elixir, :ansi_enabled)
    report = System.get_env("BYLAW_CONTRACT_REPORT")
    apps = System.get_env("BYLAW_CONTRACT_APPS")
    System.delete_env("BYLAW_CONTRACT_REPORT")
    System.delete_env("BYLAW_CONTRACT_APPS")

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:elixir, :ansi_enabled, value)
        :error -> Application.delete_env(:elixir, :ansi_enabled)
      end

      restore_env("BYLAW_CONTRACT_REPORT", report)
      restore_env("BYLAW_CONTRACT_APPS", apps)
    end)
  end

  test "colored diagnostics preserve plain wording and style every finding category" do
    coverage = fixture()
    plain = render(coverage, colors: false)
    colored = render(coverage, colors: true)
    assert strip(colored) == plain

    for category <- [
          "Missed input alternative",
          "Missed input class",
          "Missed boundary",
          "Missed return alternative",
          "Missed compiler-inferred return alternative",
          "Missed function clause"
        ] do
      assert colored =~ IO.ANSI.red() <> category <> IO.ANSI.reset()
    end

    assert colored =~ IO.ANSI.red() <> "✗" <> IO.ANSI.reset()
    assert colored =~ IO.ANSI.cyan() <> "lib/color_fixture.ex:12" <> IO.ANSI.reset()
    assert colored =~ IO.ANSI.faint() <> "      @spec"
    assert colored =~ IO.ANSI.red() <> "return: :missing" <> IO.ANSI.reset()
    assert colored =~ IO.ANSI.red() <> "      def choose(:missing)" <> IO.ANSI.reset()
  end

  test "explicitly disabled diagnostic colors emit no ANSI escapes" do
    Application.put_env(:elixir, :ansi_enabled, true)
    refute render(fixture(), colors: false) =~ "\e["
  end

  test "direct reporting defaults to the runtime ANSI setting" do
    for enabled <- [false, true] do
      Application.put_env(:elixir, :ansi_enabled, enabled)
      assert render(fixture()) == render(fixture(), colors: enabled)
    end
  end

  test "ExUnit color settings reach diagnostic rendering including explicit forcing and disabling" do
    for runtime <- [false, true], explicit <- [false, true] do
      Application.put_env(:elixir, :ansi_enabled, runtime)
      output = formatter_output(fixture(), colors: [enabled: explicit])
      assert String.contains?(output, "\e[") == explicit
      assert strip(output) == render(fixture(), colors: false)
    end

    for runtime <- [false, true] do
      Application.put_env(:elixir, :ansi_enabled, runtime)
      assert String.contains?(formatter_output(fixture(), colors: []), "\e[") == runtime
    end
  end

  test "color selection leaves silent reports summaries and coverage data unchanged" do
    coverage = fixture()
    summary = Contract.summary(coverage)

    silent = %{
      coverage
      | hits: Map.new(all_targets(coverage), &{&1.id, 1}),
        clause_outcomes: %{clause: %{selected: 1}}
    }

    unsupported = %{
      coverage
      | unknown: MapSet.new(Enum.map(all_targets(coverage), & &1.id)),
        clauses: []
    }

    for enabled <- [false, true] do
      assert render(silent, colors: enabled) == ""
      assert render(unsupported, colors: enabled) == ""
      assert formatter_output(silent, colors: [enabled: enabled]) == ""
      render(coverage, colors: enabled)
      assert Contract.summary(coverage) == summary
    end

    System.put_env("BYLAW_CONTRACT_REPORT", "summary")

    assert formatter_output(coverage, colors: [enabled: true]) ==
             formatter_output(coverage, colors: [enabled: false])

    refute formatter_output(coverage, colors: [enabled: true]) =~ "\e["
  end

  test "every styled diagnostic segment resets before subsequent output" do
    colored = render(fixture(), colors: true)
    sequences = Regex.scan(~r/\e\[[0-9;]*m/, colored) |> List.flatten()
    assert Enum.any?(sequences)
    assert rem(length(sequences), 2) == 0

    for [opening, closing] <- Enum.chunk_every(sequences, 2) do
      assert opening in [IO.ANSI.red(), IO.ANSI.cyan(), IO.ANSI.faint()]
      assert closing == IO.ANSI.reset()
    end

    assert strip(colored <> "subsequent ExUnit output") ==
             render(fixture(), colors: false) <> "subsequent ExUnit output"
  end

  defp render(coverage, options \\ nil) do
    {:ok, device} = StringIO.open("")

    try do
      if is_nil(options),
        do: Contract.print_report(coverage, device),
        else: apply(Contract, :print_report, [coverage, device, options])

      {_, result} = StringIO.contents(device)
      result
    after
      StringIO.close(device)
    end
  end

  defp formatter_output(coverage, options) do
    capture_io(fn ->
      {:ok, state} =
        ExUnitFormatter.init(
          Keyword.put(options, :bylaw_contract, checks: [{FixtureCheck, coverage: coverage}])
        )

      assert is_pid(state.tracer)

      try do
        {:noreply, stopped} = ExUnitFormatter.handle_cast({:suite_finished, %{}}, state)
        assert is_nil(stopped.tracer)
      after
        ExUnitFormatter.terminate(:normal, state)
      end
    end)
  end

  defp fixture do
    target = %{
      module: ColorFixture,
      function: :choose,
      arity: 1,
      clause: 1,
      argument: 1,
      supported?: true,
      spec_file: "lib/color_fixture.ex",
      spec_line: 12,
      spec_source: "@spec choose(:present | :missing) :: :present | :missing",
      label: ":missing"
    }

    %{
      input_classes: [
        Map.merge(target, %{id: :union, partition: :union_member}),
        Map.put(target, :id, :input)
      ],
      boundaries: [Map.put(target, :id, :boundary)],
      return_alternatives: [Map.put(target, :id, :return)],
      compiler_return_alternatives: [Map.put(target, :id, :compiler)],
      clauses: [
        %{
          id: :clause,
          module: ColorFixture,
          function: :choose,
          arity: 1,
          file: "lib/color_fixture.ex",
          line: 14,
          source: "def choose(:missing)",
          guarded?: false
        }
      ],
      hits: %{},
      calls: %{},
      return_events: %{},
      clause_outcomes: %{},
      unknown: MapSet.new(),
      warnings: []
    }
  end

  defp all_targets(coverage),
    do:
      coverage.input_classes ++
        coverage.boundaries ++
        coverage.return_alternatives ++ coverage.compiler_return_alternatives

  defp strip(text), do: Regex.replace(~r/\e\[[0-9;]*m/, text, "")
  defp restore_env(key, nil), do: System.delete_env(key)
  defp restore_env(key, value), do: System.put_env(key, value)
end
