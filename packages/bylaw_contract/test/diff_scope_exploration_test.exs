defmodule Bylaw.Contract.DiffScopeExplorationTest do
  use ExUnit.Case, async: false
  @prototype Path.expand("../qa/diff_scope/source.exs", __DIR__)
  if File.exists?(@prototype), do: Code.require_file(@prototype)
  alias BylawDiffScope.Source

  test "source selection works with explicit before and after files without Git" do
    assert {:ok, selected} = Source.select(%{}, files("def run(x), do: x"))
    assert selected == MapSet.new([{Demo, :run, 1}])
  end

  test "body head guard and spec edits select every current clause of a function" do
    before = "@spec run(integer()) :: integer(); def run(0), do: 0; def run(x) when x > 0, do: x"

    for changed <- [
          String.replace(before, "do: x", "do: x + 1"),
          String.replace(before, "run(0)", "run(1)"),
          String.replace(before, "x > 0", "x >= 0"),
          String.replace(before, ":: integer()", ":: number()")
        ] do
      assert {:ok, selected} = Source.select(files(before), files(changed))
      assert selected == MapSet.new([{Demo, :run, 1}])
    end
  end

  test "clause deletion selects the surviving function and function deletion adds no target" do
    before = files("def run(0), do: 0; def run(x), do: x; def gone(), do: :ok")
    assert {:ok, selected} = Source.select(before, files("def run(x), do: x"))
    assert selected == MapSet.new([{Demo, :run, 1}])
    assert {:ok, empty} = Source.select(before, %{})
    assert Enum.empty?(empty)
  end

  test "private functions default arities and multiple modules retain exact identities" do
    source = ~S"""
    defmodule Demo do
      def run(a, b \\ 1), do: hidden(a + b)
      defp hidden(x), do: x
      defmodule Nested do
        def value(), do: :ok
      end
    end
    defmodule Other do
      def run(), do: :ok
    end
    """

    assert {:ok, selected} = Source.select(%{}, %{"lib/demo.ex" => source})

    assert selected ==
             MapSet.new([
               {Demo, :run, 1},
               {Demo, :run, 2},
               {Demo, :hidden, 1},
               {Demo.Nested, :value, 0},
               {Other, :run, 0}
             ])
  end

  test "formatting and file moves do not create semantic obligations" do
    after_files = %{"lib/moved.ex" => "defmodule Demo do\n def run(x) do\n x + 1\n end\nend"}
    assert {:ok, empty} = Source.select(files("def run(x), do: x + 1"), after_files)
    assert Enum.empty?(empty)
  end

  test "shared type or module context changes report unsupported impact instead of empty success" do
    for {before, changed} <- [
          {"@type t() :: integer(); def run(x), do: x", "@type t() :: atom(); def run(x), do: x"},
          {"@value 1; def run(), do: @value", "@value 2; def run(), do: @value"},
          {"alias Foo; def run(), do: Foo.run()", "alias Bar, as: Foo; def run(), do: Foo.run()"}
        ] do
      assert {:error, reasons} = Source.select(files(before), files(changed))
      assert Enum.any?(reasons, &(&1.code == :unsupported_module_context))
    end
  end

  test "generated definitions and dynamic module names are explicit unsupported mappings" do
    assert {:error, reasons} =
             Source.select(%{}, files("for n <- [:a, :b], do: def(unquote(n)(), do: :ok)"))

    assert Enum.any?(reasons, &(&1.code == :unsupported_definition_context))

    assert {:error, reasons} =
             Source.select(%{}, %{
               "lib/demo.ex" => "defmodule module_name() do\ndef run(), do: :ok\nend"
             })

    assert Enum.any?(reasons, &(&1.code == :dynamic_module))
  end

  test "explicit formatter scope overrides environment while unset preserves full scope" do
    assert Source.base([], nil) == {:ok, :all}
    assert Source.base([diff_base: false], "missing") == {:ok, :all}
    assert Source.base([diff_base: "explicit"], "environment") == {:ok, "explicit"}
    assert Source.base([], "environment") == {:ok, "environment"}
    assert {:error, _} = Source.base([], "")
    assert {:error, _} = Source.base([diff_base: 42], nil)
  end

  test "invalid and empty refs missing repositories and dirty source fail explicitly" do
    repo = repository()
    assert {:error, _} = Source.git_select(repo, "")
    assert {:error, _} = Source.git_select(repo, "--help")
    assert {:error, _} = Source.git_select(repo <> "/absent", "HEAD")
    File.write!(Path.join(repo, "lib/demo.ex"), "defmodule Demo do\ndef run(), do: :dirty\nend")
    assert {:error, [%{code: :dirty_source}]} = Source.git_select(repo, "HEAD")
  end

  test "merge base supports per layer cumulative and tested synthetic merge scope" do
    repo = repository()
    base = git!(repo, ["rev-parse", "HEAD"])
    File.write!(Path.join(repo, "lib/demo.ex"), "defmodule Demo do\ndef a(), do: :a\nend")
    commit!(repo, "A")
    a = git!(repo, ["rev-parse", "HEAD"])

    File.write!(
      Path.join(repo, "lib/demo.ex"),
      "defmodule Demo do\ndef a(), do: :a\ndef b(), do: :b\nend"
    )

    commit!(repo, "B")
    assert {:ok, layer} = Source.git_select(repo, a)
    assert layer.selected == MapSet.new([{Demo, :b, 0}])
    assert {:ok, cumulative} = Source.git_select(repo, base)
    assert cumulative.selected == MapSet.new([{Demo, :a, 0}, {Demo, :b, 0}])
    git!(repo, ["checkout", "-b", "target", base])
    File.write!(Path.join(repo, "README.md"), "target update")
    commit!(repo, "target")
    target = git!(repo, ["rev-parse", "HEAD"])
    git!(repo, ["checkout", "qa-fixture"])
    git!(repo, ["merge", "--no-ff", "target", "-m", "synthetic merge"])
    assert {:ok, merged} = Source.git_select(repo, target)
    assert merged.merge_base == target
    assert merged.selected == cumulative.selected
    assert merged.head == git!(repo, ["rev-parse", "HEAD"])
  end

  test "prototype selection filters all checks before observation and compiler caps" do
    output = probe!()
    assert output =~ "selection-before-cap: ok"
  end

  test "selected observation preserves counters unknown outcomes and cleanup" do
    output = probe!()
    assert output =~ "counts-unknown-cleanup: ok"
  end

  test "moving a function past compile time attributes does not silently preserve scope" do
    before = files("@value 1; def run(), do: @value; @value 2")
    current = files("@value 1; @value 2; def run(), do: @value")
    assert {:ok, selected} = Source.select(before, current)
    assert selected == MapSet.new([{Demo, :run, 0}])
  end

  test "spec edits on generated default arities select their authored function" do
    before = files(~S"@spec run() :: integer(); def run(x \\ 1), do: x")

    current =
      Map.new(before, fn {path, source} ->
        {path, String.replace(source, "integer()", "number()")}
      end)

    assert {:ok, selected} = Source.select(before, current)
    assert selected == MapSet.new([{Demo, :run, 0}, {Demo, :run, 1}])
  end

  test "location dependent source cannot disappear from moved or reformatted scope" do
    for expression <- ["__DIR__", "__ENV__.line"] do
      before = files("def run(), do: #{expression}")
      [{_, source}] = Map.to_list(before)
      assert {:error, reasons} = Source.select(before, %{"lib/nested/demo.ex" => source})
      assert Enum.any?(reasons, &(&1.code == :location_sensitive_source))
    end
  end

  test "nested and top level lexical contexts cannot silently remap modules" do
    first = "defmodule First do; def run(), do: :nested; end"
    second = "defmodule Second do; def run(), do: First.run(); end"

    assert {:ok, selected} =
             Source.select(files("#{first}; #{second}"), files("#{second}; #{first}"))

    assert MapSet.member?(selected, {Demo.Second, :run, 0})
    child = "defmodule Child do; def run(), do: :nested; end"

    assert {:ok, selected} =
             Source.select(
               files("def run(), do: Child.run(); #{child}"),
               files("#{child}; def run(), do: Child.run()")
             )

    assert MapSet.member?(selected, {Demo, :run, 0})
    nested = "defmodule Nested do; def run(), do: Thing.duplicate(1, 2); end"
    before = files("alias String, as: Thing; #{nested}; alias List, as: Thing")
    current = files("alias String, as: Thing; alias List, as: Thing; #{nested}")
    assert {:error, _} = Source.select(before, current)

    assert {:error, _} =
             Source.select(%{}, %{
               "lib/alias.ex" =>
                 "alias Example, as: Target; defmodule Target do; def run(), do: :ok; end"
             })
  end

  test "spec aliases retain the lexical context of the declaration" do
    spec = "@spec run(Type.t()) :: :ok"
    before = files("alias String, as: Type; #{spec}; alias MapSet, as: Type; def run(_), do: :ok")

    current =
      files("alias String, as: Type; alias MapSet, as: Type; #{spec}; def run(_), do: :ok")

    assert {:ok, selected} = Source.select(before, current)
    assert selected == MapSet.new([{Demo, :run, 1}])
  end

  test "Git selection ignores inherited parent hook repository variables" do
    repo = repository()
    parent = repository()
    File.write!(Path.join(parent, "README.md"), "parent differs")
    commit!(parent, "parent")

    keys = %{
      "GIT_DIR" => Path.join(parent, ".git"),
      "GIT_WORK_TREE" => parent,
      "GIT_INDEX_FILE" => Path.join(parent, ".git/index")
    }

    original = Map.new(keys, fn {key, _} -> {key, System.get_env(key)} end)

    try do
      System.put_env(keys)
      assert {:ok, selection} = Source.git_select(repo, "HEAD")
      assert selection.head == git!(repo, ["rev-parse", "HEAD"])
    after
      Enum.each(original, fn {key, value} ->
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end)
    end
  end

  defp probe! do
    script = Path.expand("../qa/diff_scope/runtime_probe.exs", __DIR__)

    {output, status} =
      System.cmd(
        "elixir",
        ["-pa", Path.dirname(to_string(:code.which(Bylaw.Contract))), script],
        stderr_to_stdout: true
      )

    assert status == 0, output
    output
  end

  defp files(body), do: %{"lib/demo.ex" => "defmodule Demo do\n#{body}\nend\n"}

  defp repository do
    path = Path.join(System.tmp_dir!(), "bylaw-diff-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(path, "lib"))
    on_exit(fn -> File.rm_rf!(path) end)
    git!(path, ["init", "--initial-branch=qa-fixture"])
    git!(path, ["config", "user.name", "Bylaw QA"])
    git!(path, ["config", "user.email", "qa@example.invalid"])
    git!(path, ["config", "commit.gpgsign", "false"])
    git!(path, ["config", "core.hooksPath", "/dev/null"])
    File.write!(Path.join(path, "lib/demo.ex"), "defmodule Demo do\nend")
    commit!(path, "base")
    path
  end

  defp commit!(path, message) do
    git!(path, ["add", "."])
    git!(path, ["commit", "-m", message])
  end

  defp git_environment do
    for {name, _} <- System.get_env(), String.starts_with?(name, "GIT_"), do: {name, nil}
  end

  defp git!(path, args) do
    {output, status} =
      System.cmd("git", args, cd: path, stderr_to_stdout: true, env: git_environment())

    assert status == 0, output
    String.trim(output)
  end
end
