defmodule Bylaw.Contract.FormatterColorsTest do
  use ExUnit.Case, async: true, group: :contract_formatter

  test "the ExUnit runner forwards explicit color enabling to contract diagnostics" do
    output = run_formatter(false, enabled: true)
    assert output =~ "\e[31m✗\e[0m"
    assert output =~ "\e[31mMissed function clause\e[0m"
    assert output =~ "nested_result=1/1"
    assert String.ends_with?(output, "nested_result=1/1\n")
  end

  test "the ExUnit runner honors explicit color disabling on an ANSI enabled runtime" do
    output = run_formatter(true, enabled: false)
    assert output =~ "✗"
    refute output =~ "\e["
  end

  test "the ExUnit runner defaults contract colors to the runtime ANSI setting" do
    for enabled <- [false, true] do
      output = run_formatter(enabled, [])
      assert output =~ "Missed function clause"
      assert String.contains?(output, "\e[31m") == enabled
    end
  end

  test "summary mode stays escape free even when ExUnit colors are enabled" do
    output = run_formatter(true, [enabled: true], report: "summary")
    assert output =~ "Bylaw.Contract QA:"
    assert output =~ "clauses=3 clauses_selected=1"
    refute output =~ "\e["
  end

  test "the ExUnit runner stays silent when there are no contract misses" do
    output = run_formatter(true, [enabled: true], complete: true)
    assert output == "nested_result=1/1\n"
  end

  defp run_formatter(ansi_enabled, colors, options \\ []) do
    directory =
      Path.join(
        System.tmp_dir!(),
        "bylaw-colors-#{System.pid()}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    source_file = Path.join(directory, "color_target.ex")

    File.write!(source_file, """
    defmodule BylawColorTarget do
      def choose(:left), do: :ok
      def choose(:right), do: :error
      def choose(:other), do: :other
    end
    """)

    calls =
      if Keyword.get(options, :complete, false) do
        "Enum.each([:left, :right, :other], &BylawColorTarget.choose/1)"
      else
        "BylawColorTarget.choose(:left)"
      end

    source = """
    Application.put_env(:elixir, :ansi_enabled, #{inspect(ansi_enabled)})
    {:ok, _, _} = Kernel.ParallelCompiler.compile_to_path([#{inspect(source_file)}], #{inspect(directory)}, return_diagnostics: true)
    Code.prepend_path(#{inspect(directory)})
    :application.load({:application, :bylaw_color_fixture,
      [vsn: ~c"1", modules: [BylawColorTarget], applications: [:kernel, :stdlib, :elixir]]})
    ExUnit.start(autorun: false, formatters: [Bylaw.Contract.ExUnitFormatter],
      colors: #{inspect(colors)},
      bylaw_contract: [checks: [Bylaw.Contract.Check.FunctionClauses]])
    defmodule BylawColorFixtureTest do
      use ExUnit.Case
      test "observes requested clauses" do
        #{calls}
      end
    end
    result = ExUnit.run()
    IO.puts("nested_result=\#{result.total - result.failures}/\#{result.total}")
    """

    {output, status} =
      System.cmd(
        System.find_executable("elixir"),
        ["-pa", Application.app_dir(:bylaw_contract, "ebin"), "-e", source],
        env: [
          {"BYLAW_CONTRACT_APPS", "bylaw_color_fixture"},
          {"BYLAW_CONTRACT_REPORT", Keyword.get(options, :report)},
          {"ERL_FLAGS", "+S 2:2"}
        ],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert output =~ "nested_result=1/1", output
    output
  end
end
