defmodule Bylaw.Contract.TestFixtures.FormatterDiff do
  @moduledoc false

  @doc false
  @spec create() :: String.t()
  def create do
    root =
      Path.join(System.tmp_dir!(), "bylaw-formatter-diff-#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(root, "lib"))
    File.mkdir_p!(Path.join(root, "test"))
    File.write!(Path.join(root, ".gitignore"), "_build/\n")

    File.write!(Path.join(root, "mix.exs"), """
    defmodule FormatterFixture.MixProject do
      use Mix.Project
      def project, do: [app: :formatter_fixture, version: "0.1.0", elixir: "~> 1.19"]
      def application, do: [extra_applications: [:logger]]
    end
    """)

    source = """
    defmodule FormatterFixture do
      @spec selected(integer()) :: integer()
      def selected(value), do: value
      @spec untouched(atom()) :: atom()
      def untouched(value), do: value
    end
    """

    File.write!(Path.join(root, "lib/fixture.ex"), source)
    git!(root, ["init", "--initial-branch=qa-fixture"])
    git!(root, ["config", "user.name", "Bylaw QA"])
    git!(root, ["config", "user.email", "qa@example.invalid"])
    git!(root, ["config", "commit.gpgsign", "false"])
    git!(root, ["config", "core.hooksPath", "/dev/null"])
    git!(root, ["add", "."])
    git!(root, ["commit", "-m", "base"])

    File.write!(
      Path.join(root, "lib/fixture.ex"),
      String.replace(
        source,
        "def selected(value), do: value",
        "def selected(value), do: value + 1"
      )
    )

    git!(root, ["add", "lib"])
    git!(root, ["commit", "-m", "selected function change"])
    root
  end

  @doc false
  @spec run(
          root :: String.t(),
          options :: keyword(),
          environment :: list({String.t(), String.t() | nil}),
          extra :: keyword()
        ) ::
          {String.t(), non_neg_integer()}
  def run(root, options, environment \\ [], extra \\ []) do
    ebin = :code.which(Bylaw.Contract) |> to_string() |> Path.dirname()
    options = Keyword.merge([checks: [Bylaw.Contract.Check.Typespec]], options)

    ex_unit_options =
      [
        formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter],
        bylaw_contract: Keyword.get(extra, :observation_options, options),
        colors: [enabled: false]
      ]

    body =
      Keyword.get(
        extra,
        :test_body,
        "assert FormatterFixture.selected(1) == 2\nassert FormatterFixture.untouched(:ok) == :ok"
      )

    File.write!(Path.join(root, "test/test_helper.exs"), """
    Code.prepend_path(#{inspect(ebin)})
    defmodule FormatterAudit do
      def observers do
        Enum.count(Process.list(), fn pid ->
          case Process.info(pid, :dictionary) do
            {:dictionary, dict} -> Keyword.get(dict, :"$initial_call") == {Bylaw.Contract.Tracer, :init, 1}
            _ -> false
          end
        end)
      end
    end
    #{Keyword.get(extra, :before_start, "")}
    ExUnit.start(#{inspect(ex_unit_options)})
    ExUnit.after_suite(fn _ -> IO.puts("AUDIT_STOPPED=" <> Integer.to_string(FormatterAudit.observers())) end)
    """)

    File.write!(Path.join(root, "test/fixture_test.exs"), """
    defmodule FormatterFixtureTest do
      use ExUnit.Case
      test "ordinary test execution" do
        IO.puts("AUDIT_BODY")
        IO.puts("AUDIT_OBSERVERS=" <> Integer.to_string(FormatterAudit.observers()))
        #{body}
      end
    end
    """)

    environment =
      Map.new(
        clean_environment() ++
          [
            {"BYLAW_CONTRACT_REPORT", "summary"},
            {"BYLAW_CONTRACT_APPS", nil},
            {"BYLAW_CONTRACT_DIFF_BASE", nil}
          ] ++ environment
      )
      |> Map.to_list()

    arguments = Keyword.get(extra, :mix_args, ["test"])

    arguments =
      case Keyword.fetch(extra, :exit_status) do
        {:ok, status} -> arguments ++ ["--exit-status", Integer.to_string(status)]
        :error -> arguments
      end

    System.cmd("mix", arguments,
      cd: root,
      env: environment,
      stderr_to_stdout: true
    )
  end

  @doc false
  @spec git!(String.t(), list(String.t())) :: String.t()
  def git!(root, args) do
    case System.cmd("git", args, cd: root, env: clean_environment(), stderr_to_stdout: true) do
      {output, 0} -> String.trim(output)
      {output, status} -> raise "fixture Git failed (#{status}): #{output}"
    end
  end

  defp clean_environment do
    for {key, _} <- System.get_env(), String.starts_with?(key, "GIT_"), do: {key, nil}
  end
end
