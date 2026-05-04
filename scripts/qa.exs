defmodule Bylaw.Dev.Qa do
  @moduledoc false

  @qa_env "test"

  @typep command_args :: list(String.t())
  @typep command_result :: %{
           exit_code: integer(),
           output: String.t(),
           stage: String.t()
         }
  @typep command_context :: %{
           cwd: String.t(),
           env: list({String.t(), String.t()}),
           elixir_executable: String.t(),
           shell_executable: String.t()
         }
  @typep stage :: %{label: String.t(), commands: list(command_args())}
  @typep stage_result :: %{
           label: String.t(),
           results: list(command_result()),
           status: :ok | :error
         }
  @typep qa_options :: %{coverage: boolean(), failures_only: boolean()}
  @typep coverage_row :: {percentage_hundredths :: non_neg_integer(), module_name :: String.t()}
  @mix_runner_prefix ["--erl", "-elixir ansi_enabled true", "-S", "mix"]
  @coverage_open_file_limit 2048
  @default_coverage_threshold_hundredths 9000
  @coverage_row_regex ~r/^\|\s*([0-9]+\.[0-9]+)%\s+\|\s+(.+?)\s+\|$/
  @ansi_escape_regex ~r/\e\[[\d;]*m/

  @prep_stage %{
    label: "prep",
    commands: [
      ["deps.unlock", "--unused"],
      ["format"],
      ["compile", "--warnings-as-errors"],
      ["hex.audit"],
      ["deps.audit"]
    ]
  }

  @doc false
  @spec run(args :: list(String.t())) :: :ok
  def run(args) do
    options = parse_args!(args)

    context = %{
      cwd: File.cwd!(),
      env: command_env(),
      elixir_executable: find_elixir_executable!(),
      shell_executable: find_shell_executable!()
    }

    prep_result = run_stage(@prep_stage, context)
    print_stage_result(prep_result, options)
    raise_on_failure!([prep_result])

    parallel_stages = parallel_stages(options)

    parallel_results =
      parallel_stages
      |> Task.async_stream(&run_stage(&1, context),
        max_concurrency: Enum.count(parallel_stages),
        ordered: false,
        timeout: :infinity
      )
      |> Enum.map(fn
        {:ok, result} ->
          print_stage_result(result, options)
          result

        {:exit, reason} ->
          Mix.raise("qa stage crashed: #{inspect(reason)}")
      end)

    raise_on_failure!(parallel_results)
    :ok
  end

  @spec parse_args!(args :: list(String.t())) :: qa_options()
  defp parse_args!(args) do
    {parsed, positional} =
      OptionParser.parse!(args, strict: [coverage: :boolean, failures_only: :boolean])

    case positional do
      [] ->
        %{
          coverage: Keyword.get(parsed, :coverage, false),
          failures_only: Keyword.get(parsed, :failures_only, false)
        }

      unexpected ->
        Mix.raise("mix qa does not accept positional arguments: #{Enum.join(unexpected, " ")}")
    end
  end

  @spec parallel_stages(options :: qa_options()) :: list(stage())
  defp parallel_stages(options) do
    [
      %{
        label: "credo",
        commands: [
          ["credo", "suggest", "--strict", "--verbose"]
        ]
      },
      %{
        label: "docs",
        commands: [
          ["docs", "--warnings-as-errors"]
        ]
      },
      %{
        label: "dialyzer",
        commands: [
          ["dialyzer", "--no-compile", "--quiet-with-result"]
        ]
      },
      %{
        label: "test",
        commands: [
          test_command(options)
        ]
      }
    ]
  end

  @spec test_command(options :: qa_options()) :: command_args()
  defp test_command(%{coverage: true}), do: ["test", "--cover", "--no-compile"]
  defp test_command(_options), do: ["test", "--no-compile"]

  @spec run_stage(stage :: stage(), context :: command_context()) :: stage_result()
  defp run_stage(stage, context) do
    stage
    |> do_run_stage(context)
    |> Map.update!(:results, &Enum.reverse/1)
  end

  @spec do_run_stage(stage :: stage(), context :: command_context()) :: stage_result()
  defp do_run_stage(stage, context) do
    Enum.reduce_while(stage.commands, %{label: stage.label, results: [], status: :ok}, fn command,
                                                                                          acc ->
      case run_command(stage.label, command, context) do
        {:ok, result} ->
          {:cont, %{acc | results: [result | acc.results]}}

        {:error, result} ->
          {:halt, %{acc | results: [result | acc.results], status: :error}}
      end
    end)
  end

  @spec run_command(label :: String.t(), args :: command_args(), context :: command_context()) ::
          {:ok, command_result()} | {:error, command_result()}
  defp run_command(label, args, context) do
    {output, exit_code} =
      if coverage_command?(args) do
        System.cmd(context.shell_executable, ["-c", coverage_shell_command(args, context)],
          cd: context.cwd,
          env: context.env,
          stderr_to_stdout: true
        )
      else
        System.cmd(context.elixir_executable, @mix_runner_prefix ++ args,
          cd: context.cwd,
          env: context.env,
          stderr_to_stdout: true
        )
      end

    result = %{exit_code: exit_code, output: output, stage: label}

    case exit_code do
      0 -> {:ok, result}
      _code -> {:error, result}
    end
  end

  @spec print_stage_result(stage_result :: stage_result(), options :: qa_options()) :: :ok
  defp print_stage_result(stage_result, options) do
    %{label: label, status: status} = stage_result

    Mix.shell().info("==> #{label} (#{status})")
    maybe_print_stage_output(stage_result, options)

    :ok
  end

  @spec maybe_print_stage_output(stage_result :: stage_result(), options :: qa_options()) :: :ok
  defp maybe_print_stage_output(%{status: :error} = stage_result, _options),
    do: print_results(stage_result.results)

  defp maybe_print_stage_output(%{label: "test", status: :ok} = stage_result, %{coverage: true}) do
    print_filtered_coverage(stage_result.results)
  end

  defp maybe_print_stage_output(%{status: :ok} = stage_result, %{failures_only: false}),
    do: print_results(stage_result.results)

  defp maybe_print_stage_output(_stage_result, _options), do: :ok

  @spec print_results(results :: list(command_result())) :: :ok
  defp print_results(results) do
    Enum.each(results, fn result ->
      output = String.trim_trailing(result.output)

      if output != "" do
        Mix.shell().info(output)
      end
    end)
  end

  @spec print_filtered_coverage(results :: list(command_result())) :: :ok
  defp print_filtered_coverage(results) do
    case extract_coverage_rows(results) do
      [] ->
        print_results(results)

      coverage_rows ->
        threshold = coverage_threshold()

        coverage_rows
        |> Enum.filter(&poor_coverage_row?(&1, threshold))
        |> print_coverage_rows(threshold)
    end
  end

  @spec extract_coverage_rows(results :: list(command_result())) :: list(coverage_row())
  defp extract_coverage_rows(results) do
    results
    |> Enum.flat_map(fn result ->
      output = result.output

      output
      |> String.split("\n")
      |> Enum.map(&parse_coverage_row/1)
    end)
    |> Enum.reject(&is_nil/1)
  end

  @spec parse_coverage_row(line :: String.t()) :: coverage_row() | nil
  defp parse_coverage_row(line) do
    cleaned_line = strip_ansi(line)

    case Regex.run(@coverage_row_regex, cleaned_line, capture: :all_but_first) do
      [percentage, module_name] ->
        {parse_percentage(percentage), String.trim(module_name)}

      _other ->
        nil
    end
  end

  @spec poor_coverage_row?(row :: coverage_row(), threshold_hundredths :: non_neg_integer()) ::
          boolean()
  defp poor_coverage_row?({_percentage, "Total"}, _threshold), do: true
  defp poor_coverage_row?({percentage, _module_name}, threshold), do: percentage < threshold

  @spec print_coverage_rows(
          rows :: list(coverage_row()),
          threshold_hundredths :: non_neg_integer()
        ) :: :ok
  defp print_coverage_rows(rows, threshold) do
    Mix.shell().info("Coverage below #{format_percentage(threshold)}:")

    Enum.each(rows, fn {percentage, module_name} ->
      Mix.shell().info([
        "  ",
        coverage_row_color(percentage, module_name, threshold),
        format_percentage(percentage),
        :reset,
        " ",
        module_name
      ])
    end)
  end

  @spec coverage_row_color(
          percentage_hundredths :: non_neg_integer(),
          module_name :: String.t(),
          threshold_hundredths :: non_neg_integer()
        ) :: atom()
  defp coverage_row_color(percentage, "Total", threshold) when percentage >= threshold, do: :green
  defp coverage_row_color(_percentage, _module_name, _threshold), do: :red

  @spec coverage_threshold() :: non_neg_integer()
  defp coverage_threshold do
    Mix.Project.config()
    |> Keyword.get(:test_coverage, [])
    |> Keyword.get(:summary, true)
    |> summary_threshold()
  end

  @spec summary_threshold(summary :: true | false | keyword()) :: non_neg_integer()
  defp summary_threshold(true), do: @default_coverage_threshold_hundredths
  defp summary_threshold(false), do: @default_coverage_threshold_hundredths

  defp summary_threshold(summary_options) when is_list(summary_options) do
    summary_options
    |> Keyword.get(:threshold, 90)
    |> to_string()
    |> parse_percentage()
  end

  @spec parse_percentage(value :: String.t()) :: non_neg_integer()
  defp parse_percentage(value) do
    case String.split(value, ".", parts: 2) do
      [whole] ->
        String.to_integer(whole) * 100

      [whole, fraction] ->
        normalized_fraction =
          fraction
          |> String.pad_trailing(2, "0")
          |> String.slice(0, 2)

        String.to_integer(whole) * 100 + String.to_integer(normalized_fraction)
    end
  end

  @spec format_percentage(value_hundredths :: non_neg_integer()) :: String.t()
  defp format_percentage(value_hundredths) do
    whole = div(value_hundredths, 100)
    remainder = rem(value_hundredths, 100)

    fraction =
      remainder
      |> Integer.to_string()
      |> String.pad_leading(2, "0")

    "#{whole}.#{fraction}%"
  end

  @spec strip_ansi(line :: String.t()) :: String.t()
  defp strip_ansi(line), do: Regex.replace(@ansi_escape_regex, line, "")

  @spec raise_on_failure!(stage_results :: list(stage_result())) :: :ok
  defp raise_on_failure!(stage_results) do
    failures =
      stage_results
      |> Enum.filter(&(&1.status == :error))
      |> Enum.map(& &1.label)

    case failures do
      [] ->
        :ok

      failed_labels ->
        Mix.raise("qa failed in stages: #{Enum.join(failed_labels, ", ")}")
    end
  end

  @spec command_env() :: list({String.t(), String.t()})
  defp command_env do
    [
      {"MIX_ENV", System.get_env("MIX_ENV", @qa_env)},
      {"MIX_BUILD_PATH", Mix.Project.build_path()}
    ] ++
      mix_target_env()
  end

  @spec find_elixir_executable!() :: String.t()
  defp find_elixir_executable! do
    System.find_executable("elixir") || Mix.raise("elixir executable not found in PATH")
  end

  @spec find_shell_executable!() :: String.t()
  defp find_shell_executable! do
    case System.get_env("SHELL") do
      shell when is_binary(shell) and shell != "" ->
        if File.exists?(shell) do
          shell
        else
          fallback_shell_executable!()
        end

      _other ->
        fallback_shell_executable!()
    end
  end

  @spec mix_target_env() :: list({String.t(), String.t()})
  defp mix_target_env do
    case System.get_env("MIX_TARGET") do
      nil -> []
      target -> [{"MIX_TARGET", target}]
    end
  end

  @spec coverage_command?(args :: command_args()) :: boolean()
  defp coverage_command?(args), do: "--cover" in args

  @spec coverage_shell_command(args :: command_args(), context :: command_context()) :: String.t()
  defp coverage_shell_command(args, context) do
    mix_command =
      Enum.map_join(
        [context.elixir_executable | @mix_runner_prefix ++ args],
        " ",
        &shell_escape/1
      )

    """
    current_limit=$(ulimit -n)
    if [ "$current_limit" -lt "#{@coverage_open_file_limit}" ]; then
      ulimit -n "#{@coverage_open_file_limit}" || {
        echo "Failed to raise open file limit to #{@coverage_open_file_limit} for coverage run" >&2
        exit 1
      }
    fi
    exec #{mix_command}
    """
  end

  @spec shell_escape(arg :: String.t()) :: String.t()
  defp shell_escape(arg), do: "'#{String.replace(arg, "'", ~s('"'"'))}'"

  @spec fallback_shell_executable!() :: String.t()
  defp fallback_shell_executable! do
    System.find_executable("zsh") ||
      System.find_executable("sh") ||
      Mix.raise("shell executable not found in PATH")
  end
end
