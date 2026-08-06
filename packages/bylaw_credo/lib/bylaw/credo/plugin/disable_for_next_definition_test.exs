defmodule Bylaw.Credo.Plugin.DisableForNextDefinitionTest.DefinitionLineCheck do
  @moduledoc false

  use Credo.Check, base_priority: :high, category: :warning

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({kind, meta, _arguments} = ast, ctx) when kind in [:def, :defp] do
    issue =
      format_issue(ctx, line_no: meta[:line], trigger: to_string(kind), message: "definition")

    {ast, put_issue(ctx, issue)}
  end

  defp walk(ast, ctx), do: {ast, ctx}
end

defmodule Bylaw.Credo.Plugin.DisableForNextDefinitionTest.MarkerCheck do
  @moduledoc false

  use Credo.Check, base_priority: :high, category: :warning

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:marker, meta, _arguments} = ast, ctx) do
    issue = format_issue(ctx, line_no: meta[:line], trigger: "marker", message: "marker")
    {ast, put_issue(ctx, issue)}
  end

  defp walk(ast, ctx), do: {ast, ctx}
end

defmodule Bylaw.Credo.Plugin.DisableForNextDefinitionTest.MarkerCheckExtra do
  @moduledoc false

  use Credo.Check, base_priority: :high, category: :warning

  @impl Credo.Check
  def run(source_file, params \\ []) do
    ctx = Context.build(source_file, params, __MODULE__)
    Credo.Code.prewalk(source_file, &walk/2, ctx).issues
  end

  defp walk({:marker_extra, meta, _arguments} = ast, ctx) do
    issue = format_issue(ctx, line_no: meta[:line], trigger: "marker_extra", message: "extra")
    {ast, put_issue(ctx, issue)}
  end

  defp walk(ast, ctx), do: {ast, ctx}
end

defmodule Bylaw.Credo.Plugin.DisableForNextDefinitionTest do
  use ExUnit.Case, async: false

  alias Bylaw.Credo.Check.Elixir.NoRaise
  alias Bylaw.Credo.Plugin.DisableForNextDefinition.ResolveRanges
  alias Bylaw.Credo.Plugin.DisableForNextDefinitionTest.DefinitionLineCheck
  alias Bylaw.Credo.Plugin.DisableForNextDefinitionTest.MarkerCheck
  alias Bylaw.Credo.Plugin.DisableForNextDefinitionTest.MarkerCheckExtra
  alias Credo.Check.ConfigComment
  alias Credo.CLI.Filter
  alias Credo.Execution
  alias Credo.Issue

  test "suppresses a named check reported on the definition line" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(DefinitionLineCheck)}
      def run, do: :ok
    end
    """

    assert no_issues?(source, [DefinitionLineCheck])
  end

  test "suppresses NoRaise many lines into a function body" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(NoRaise)}
      def run do
        :first
        :second
        :third
        :fourth
        raise "failure"
      end
    end
    """

    assert no_issues?(source, [NoRaise])
  end

  test "leaves a different check inside the same function visible" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
      def run do
        marker()
        marker_extra()
      end
    end
    """

    assert [%Issue{check: MarkerCheckExtra, line_no: 5}] =
             run_issues(source, [MarkerCheck, MarkerCheckExtra])
  end

  test "leaves the same named check in the following function visible" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
      def first, do: marker()
      def second, do: marker()
    end
    """

    assert [%Issue{check: MarkerCheck, line_no: 4}] = run_issues(source, [MarkerCheck])
  end

  test "keeps suppression aligned after body lines are added or removed" do
    short_source = function_with_body(["marker()"])
    long_source = function_with_body([":one", ":two", ":three", "marker()", ":four"])

    assert no_issues?(short_source, [MarkerCheck])
    assert no_issues?(long_source, [MarkerCheck])
  end

  test "suppresses issues in a one-line definition" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(NoRaise)}
      def value, do: raise("failure")
    end
    """

    assert no_issues?(source, [NoRaise])
  end

  test "uses the outer definition end when nested blocks are present" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
      def run do
        if ready?() do
          case value() do
            :ok -> marker()
            _ -> fn -> marker() end
          end
        end
      end
    end
    """

    assert no_issues?(source, [MarkerCheck])
  end

  test "a parameterless directive suppresses every check in the definition" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition
      def run do
        marker()
        marker_extra()
      end
    end
    """

    assert no_issues?(source, [MarkerCheck, MarkerCheckExtra])
  end

  test "matches exact check modules with Credo config-comment semantics" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
      def run do
        marker()
        marker_extra()
      end
    end
    """

    assert [%Issue{check: MarkerCheckExtra}] =
             run_issues(source, [MarkerCheck, MarkerCheckExtra])
  end

  test "suppresses only the next syntactic clause of a multi-clause function" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
      def run(:first), do: marker()
      def run(:second), do: marker()
    end
    """

    assert [%Issue{check: MarkerCheck, line_no: 4}] = run_issues(source, [MarkerCheck])
  end

  test "a directive without a following definition suppresses nothing" do
    source = """
    defmodule Example do
      def first, do: marker()
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
    end
    """

    assert [%Issue{check: MarkerCheck, line_no: 2}] = run_issues(source, [MarkerCheck])
  end

  test "directive-like strings heredocs and sigils are ignored" do
    source = ~S'''
    defmodule Example do
      @string "# credo:disable-for-next-definition Bylaw.Credo.Plugin.DisableForNextDefinitionTest.MarkerCheck"
      @heredoc """
      # credo:disable-for-next-definition Bylaw.Credo.Plugin.DisableForNextDefinitionTest.MarkerCheck
      """
      @sigil ~S(# credo:disable-for-next-definition Bylaw.Credo.Plugin.DisableForNextDefinitionTest.MarkerCheck)
      def run, do: marker()
    end
    '''

    assert [%Issue{check: MarkerCheck, line_no: 7}] = run_issues(source, [MarkerCheck])
  end

  test "definitions inside quote blocks are not suppression targets" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
      quote do
        def generated, do: marker()
      end

      def run, do: marker()
    end
    """

    line_nos =
      source
      |> run_issues([MarkerCheck])
      |> Enum.map(& &1.line_no)

    assert line_nos == [4]
  end

  test "the plugin registers for the default Suggest and List command paths" do
    source = function_with_body(["marker()"])

    default_exec = run_credo(source, [MarkerCheck])
    suggest_exec = run_credo(source, [MarkerCheck], "suggest")
    list_exec = run_credo(source, [MarkerCheck], "list")

    assert empty_issues?(default_exec)
    assert empty_issues?(suggest_exec)
    assert empty_issues?(list_exec)
  end

  test "the plugin resolves definition ranges on the Diff command path" do
    source = function_with_body(["marker()"])

    exec = run_credo(source, [MarkerCheck], ["diff", "--from-dir", __DIR__])

    assert exec.config_comment_map
           |> Map.values()
           |> List.flatten()
           |> Enum.any?(&(&1.instruction == "disable-for-lines"))
  end

  test "filtered issue counts and exit status exclude suppressed issues" do
    source = function_with_body(["marker()"])
    exec = run_credo(source, [MarkerCheck])

    assert empty_issues?(exec)
    assert Execution.get_exit_status(exec) == 0
  end

  test "does not cross module protocol implementation or nested-module boundaries" do
    source = """
    defmodule Outer do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
      defmodule Inner do
        def run, do: marker()
      end

      def after_inner, do: marker()
    end

    defprotocol ExampleProtocol do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
    end

    defimpl ExampleProtocol, for: Atom do
      def run, do: marker()
    end
    """

    line_nos =
      source
      |> run_issues([MarkerCheck])
      |> Enum.map(& &1.line_no)

    assert line_nos == [4, 7, 15]
  end

  test "supports private definitions and comments or blank lines before a definition" do
    source = """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}

      # an ordinary comment may separate the directive
      defp run do
        marker()
      end
    end
    """

    assert no_issues?(source, [MarkerCheck])
  end

  test "issues without usable filenames or line numbers are not suppressed" do
    comment = %ConfigComment{
      instruction: "disable-for-lines",
      line_no: 2,
      line_no_end: 4,
      params: []
    }

    exec = %Execution{config_comment_map: %{"sample.ex" => [comment]}}

    refute Filter.ignored_by_config_comment?(%Issue{filename: nil, line_no: 3}, exec)
    refute Filter.ignored_by_config_comment?(%Issue{filename: "sample.ex", line_no: nil}, exec)
  end

  test "fails closed when an exact AST range is unavailable" do
    source_ast =
      Code.string_to_quoted!(
        """
        defmodule Example do
          # credo:disable-for-next-definition #{inspect(MarkerCheck)}
          def run, do: marker()
        end
        """,
        columns: true,
        token_metadata: true
      )

    ast =
      Macro.prewalk(source_ast, fn
        {:def, meta, arguments} ->
          {:def, Keyword.drop(meta, [:end, :end_of_expression]), arguments}

        node ->
          node
      end)

    directive = ConfigComment.new("disable-for-next-definition", inspect(MarkerCheck), 2)
    resolved_comments = ResolveRanges.resolve(ast, [directive])

    assert Enum.empty?(resolved_comments)
  end

  defp function_with_body(body_lines) do
    body = Enum.map_join(body_lines, "\n", &"    #{&1}")

    """
    defmodule Example do
      # credo:disable-for-next-definition #{inspect(MarkerCheck)}
      def run do
    #{body}
      end
    end
    """
  end

  defp run_credo(source, checks, command \\ nil) do
    test_dir =
      Path.join(
        System.tmp_dir!(),
        "bylaw-credo-next-definition-#{System.unique_integer([:positive])}"
      )

    source_path = Path.join(test_dir, "sample.ex")
    config_path = Path.join(test_dir, ".credo.exs")
    File.mkdir_p!(test_dir)
    File.write!(source_path, source)
    File.write!(config_path, config(checks, source_path))
    on_exit(fn -> File.rm_rf!(test_dir) end)

    command_args =
      command
      |> List.wrap()
      |> Enum.reject(&is_nil/1)

    args = command_args ++ ["--config-file", config_path, "--format", "oneline"]

    Credo.run(args)
  end

  defp config(checks, source_path) do
    checks = Enum.map_join(checks, ",\n", &"          {#{inspect(&1)}, []}")

    """
    %{
      configs: [
        %{
          name: "default",
          color: false,
          files: %{included: [#{inspect(source_path)}], excluded: []},
          plugins: [{Bylaw.Credo.Plugin.DisableForNextDefinition, []}],
          checks: %{enabled: [
    #{checks}
          ]}
        }
      ]
    }
    """
  end

  defp issues(exec), do: Execution.get_issues(exec)

  defp run_issues(source, checks) do
    source
    |> run_credo(checks)
    |> issues()
  end

  defp no_issues?(source, checks) do
    source
    |> run_issues(checks)
    |> Enum.empty?()
  end

  defp empty_issues?(exec) do
    exec
    |> issues()
    |> Enum.empty?()
  end
end
