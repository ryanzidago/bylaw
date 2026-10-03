defmodule Bylaw.Contract.ChangedCodeAcceptanceTest do
  use ExUnit.Case

  alias Bylaw.Contract.ChangedCode
  alias Bylaw.Contract.Property
  alias Bylaw.Contract.Report

  @committed """
  defmodule Sample do
    @spec first(integer()) :: :ok
    def first(1), do: :ok
    def first(_other), do: :ok

    @spec second(integer()) :: :ok
    def second(1), do: :ok
    def second(_other) do
      :ok
    end
  end
  """

  setup do
    dir = Path.join(System.tmp_dir!(), "bylaw-changed-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    git(dir, ["init", "-q"])
    File.write!(Path.join(dir, "sample.ex"), @committed)
    git(dir, ["add", "."])
    git(dir, ["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "base"])
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "keeps only the findings of functions that changed since a git revision", %{dir: dir} do
    file = Path.join(dir, "sample.ex")
    File.write!(file, String.replace(@committed, "    :ok\n  end", "    :changed\n  end"))

    report = report(file)

    kept = ChangedCode.filter(report, since: "HEAD", cd: dir)

    assert functions(kept) == [:second]
  end

  test "keeps a function whose spec line changed", %{dir: dir} do
    file = Path.join(dir, "sample.ex")
    File.write!(file, String.replace(@committed, "first(integer())", "first(pos_integer())"))

    kept = ChangedCode.filter(report(file), since: "HEAD", cd: dir)

    assert functions(kept) == [:first]
  end

  test "keeps every finding of a file that git does not track yet", %{dir: dir} do
    file = Path.join(dir, "fresh.ex")
    File.write!(file, String.replace(@committed, "Sample", "Fresh"))

    kept = ChangedCode.filter(report(file), since: "HEAD", cd: dir)

    assert functions(kept) == [:first, :second]
  end

  test "keeps nothing when nothing changed", %{dir: dir} do
    kept = ChangedCode.filter(report(Path.join(dir, "sample.ex")), since: "HEAD", cd: dir)

    assert functions(kept) == []
  end

  test "reports a clear error for a revision git does not know", %{dir: dir} do
    assert_raise ArgumentError, ~r/unknown-revision/, fn ->
      ChangedCode.filter(report(Path.join(dir, "sample.ex")), since: "unknown-revision", cd: dir)
    end
  end

  defp report(file) do
    properties = [
      property(file, :first, 3, :clause),
      property(file, :second, 7, :clause),
      property(file, :first, 2, :return_alternative),
      property(file, :second, 6, :return_alternative)
    ]

    %Report{properties: properties}
  end

  defp property(file, function, line, kind) do
    struct!(Property,
      id: {kind, function, line},
      kind: kind,
      module: Sample,
      function: function,
      arity: 1,
      file: file,
      line: line,
      status: :missed
    )
  end

  defp functions(report),
    do: report |> Report.missed() |> Enum.map(& &1.function) |> Enum.uniq() |> Enum.sort()

  defp git(dir, arguments) do
    {_output, 0} =
      System.cmd("git", ["-c", "core.hooksPath=/dev/null" | arguments],
        cd: dir,
        stderr_to_stdout: true,
        env: [{"GIT_DIR", nil}, {"GIT_WORK_TREE", nil}, {"GIT_INDEX_FILE", nil}]
      )
  end
end
