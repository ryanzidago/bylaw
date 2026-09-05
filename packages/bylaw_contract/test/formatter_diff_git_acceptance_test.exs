defmodule Bylaw.Contract.FormatterDiffGitAcceptanceTest do
  use ExUnit.Case, async: false
  alias Bylaw.Contract.TestFixtures.FormatterDiff

  setup do
    root = FormatterDiff.create()
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "missing Git repository history and common ancestry produce explicit failures" do
    for mode <- [:git, :repository, :history, :ancestry] do
      root = FormatterDiff.create()

      try do
        {ref, extra} =
          case mode do
            :git ->
              {"HEAD~1", [before_start: "System.put_env(\"PATH\", \"\")"]}

            :repository ->
              File.rm_rf!(Path.join(root, ".git"))
              {"HEAD~1", []}

            :history ->
              head = FormatterDiff.git!(root, ["rev-parse", "HEAD"])
              File.write!(Path.join(root, ".git/shallow"), head <> "\n")
              {"HEAD~1", []}

            :ancestry ->
              FormatterDiff.git!(root, ["checkout", "--orphan", "unrelated"])
              FormatterDiff.git!(root, ["commit", "-m", "unrelated history"])
              FormatterDiff.git!(root, ["checkout", "qa-fixture"])
              {"unrelated", []}
          end

        {output, status} = FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", ref}], extra)
        assert status == 2, "#{mode}: #{output}"
        assert output =~ "AUDIT_BODY"
        assert output =~ "AUDIT_OBSERVERS=0"
        assert output =~ "AUDIT_STOPPED=0"
      after
        File.rm_rf!(root)
      end
    end
  end

  test "empty whitespace and wrong typed diff options never fall back to full scope", %{
    root: root
  } do
    for ref <- ["", "   ", 42, nil, true] do
      {output, status} = FormatterDiff.run(root, diff_base: ref)
      assert status == 2, output
      assert output =~ "invalid_diff_base"
      assert output =~ "AUDIT_BODY"
      assert output =~ "AUDIT_OBSERVERS=0"
    end
  end

  test "repository local inherited Git variables cannot redirect source selection", %{root: root} do
    other = FormatterDiff.create()

    try do
      environment = [
        {"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"},
        {"GIT_DIR", Path.join(other, ".git")},
        {"GIT_WORK_TREE", other},
        {"GIT_INDEX_FILE", Path.join(other, ".git/index")}
      ]

      File.write!(Path.join(other, "lib/fixture.ex"), "# dirty unrelated synthetic repository")
      {output, status} = FormatterDiff.run(root, [], environment)
      assert status == 0, output
      assert output =~ "functions=1"
      assert output =~ "AUDIT_OBSERVERS=1"
      assert output =~ "AUDIT_STOPPED=0"
    after
      File.rm_rf!(other)
    end
  end

  test "source paths are validated before Git execution", %{root: root} do
    for paths <- [[], [""], ["../outside"], ["/absolute"], [:lib], "lib"] do
      {output, status} = FormatterDiff.run(root, diff_base: "HEAD~1", diff_paths: paths)
      assert status == 2, output
      assert output =~ "invalid_diff_paths"
      assert output =~ "AUDIT_BODY"
      assert output =~ "AUDIT_OBSERVERS=0"
    end
  end

  test "unsupported source mapping is unsuccessful even with passing tests", %{root: root} do
    path = Path.join(root, "lib/fixture.ex")

    source =
      File.read!(path)
      |> String.replace(
        "defmodule FormatterFixture do",
        "defmodule FormatterFixture do\n @compile {:inline, selected: 1}"
      )

    File.write!(path, source)
    FormatterDiff.git!(root, ["add", "lib"])
    FormatterDiff.git!(root, ["commit", "-m", "compiler context"])
    {output, status} = FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"}])
    assert status == 2, output
    assert output =~ "unsupported_definition_context"
    assert output =~ "Result: 1 passed"
    assert output =~ "AUDIT_STOPPED=0"
  end

  test "selected source modules missing from the application cannot disappear by intersection", %{
    root: root
  } do
    File.mkdir_p!(Path.join(root, "external"))

    File.write!(
      Path.join(root, "external/extra.ex"),
      "defmodule OutsideFormatterApp do; def run(), do: :ok; end"
    )

    FormatterDiff.git!(root, ["add", "external"])
    FormatterDiff.git!(root, ["commit", "-m", "source outside application"])

    {output, status} =
      FormatterDiff.run(root, diff_base: "HEAD~1", diff_paths: ["lib", "external"])

    assert status == 2, output
    assert output =~ "selected_module_not_in_application"
    assert output =~ "Result: 1 passed"
    assert output =~ "AUDIT_OBSERVERS=0"
  end

  test "stale compiled sources and mismatched loaded BEAMs are rejected", %{root: root} do
    {output, 0} = FormatterDiff.run(root, [])
    assert output =~ "Result: 1 passed"
    path = Path.join(root, "lib/fixture.ex")
    File.write!(path, String.replace(File.read!(path), "value + 1", "1 + value"))
    FormatterDiff.git!(root, ["add", "lib"])
    FormatterDiff.git!(root, ["commit", "-m", "new source with stale beam"])

    {output, status} =
      FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"}],
        mix_args: ["test", "--no-compile"]
      )

    assert status == 2, output
    assert output =~ "compiled_source_mismatch"
    assert output =~ "Result: 1 passed"

    replacement_root = FormatterDiff.create()

    try do
      replacement =
        "defmodule FormatterFixture do; def selected(value), do: value + 1; def untouched(value), do: value; def extra(), do: :extra; end"

      {output, status} =
        FormatterDiff.run(replacement_root, [], [{"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"}],
          before_start: "Code.compile_string(#{inspect(replacement)})"
        )

      assert status == 2, output
      assert output =~ "loaded_beam_mismatch"
      assert output =~ "Result: 1 passed"
      assert output =~ "AUDIT_STOPPED=0"
    after
      File.rm_rf!(replacement_root)
    end
  end

  test "per layer cumulative synthetic merge and rebased history use the tested HEAD merge base",
       %{root: root} do
    base = FormatterDiff.git!(root, ["rev-parse", "HEAD~1"])
    first = FormatterDiff.git!(root, ["rev-parse", "HEAD"])
    path = Path.join(root, "lib/fixture.ex")

    File.write!(
      path,
      String.replace(
        File.read!(path),
        "def untouched(value),",
        "def untouched(value) when is_atom(value),"
      )
    )

    FormatterDiff.git!(root, ["add", "lib"])
    FormatterDiff.git!(root, ["commit", "-m", "second layer"])
    second = FormatterDiff.git!(root, ["rev-parse", "HEAD"])
    assert_scope(root, first, 1)
    assert_scope(root, base, 2)

    FormatterDiff.git!(root, ["checkout", "-b", "target", base])
    File.write!(Path.join(root, "README.md"), "target changes")
    FormatterDiff.git!(root, ["add", "README.md"])
    FormatterDiff.git!(root, ["commit", "-m", "target branch"])
    FormatterDiff.git!(root, ["checkout", "qa-fixture"])
    FormatterDiff.git!(root, ["merge", "--no-ff", "target", "-m", "synthetic merge"])
    assert_scope(root, "target", 2)

    FormatterDiff.git!(root, ["checkout", "-b", "rebased", second])
    FormatterDiff.git!(root, ["rebase", "target"])
    assert_scope(root, "target", 2)
    assert_scope(root, "HEAD~1", 1)
  end

  test "nested Mix projects resolve default and explicit diff roots against the enclosing repository",
       %{root: root} do
    nested = Path.join(root, "apps/fixture")
    File.mkdir_p!(nested)

    for path <- ["lib", "test", "mix.exs"] do
      File.rename!(Path.join(root, path), Path.join(nested, path))
    end

    FormatterDiff.git!(root, ["add", "-A"])
    FormatterDiff.git!(root, ["commit", "-m", "nested Mix project"])
    path = Path.join(nested, "lib/fixture.ex")

    File.write!(
      path,
      String.replace(
        File.read!(path),
        "def selected(value),",
        "def selected(value) when is_integer(value),"
      )
    )

    FormatterDiff.git!(root, ["add", "apps/fixture/lib"])
    FormatterDiff.git!(root, ["commit", "-m", "nested source change"])

    for options <- [[], [diff_root: nested]] do
      {output, status} =
        FormatterDiff.run(nested, options, [{"BYLAW_CONTRACT_DIFF_BASE", "HEAD~1"}])

      assert status == 0, output
      assert output =~ "functions=1 "
      assert output =~ "AUDIT_OBSERVERS=1"
      assert output =~ "AUDIT_STOPPED=0"
    end
  end

  defp assert_scope(root, reference, functions) do
    {output, status} = FormatterDiff.run(root, [], [{"BYLAW_CONTRACT_DIFF_BASE", reference}])
    assert status == 0, output
    assert output =~ "functions=#{functions} "
    assert Enum.count(Regex.scan(~r/AUDIT_BODY/, output)) == 1
    assert output =~ "AUDIT_OBSERVERS=1"
    assert output =~ "AUDIT_STOPPED=0"
  end
end
