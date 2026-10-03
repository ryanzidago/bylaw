defmodule Bylaw.Contract.ChangedCode do
  @moduledoc """
  Restricts a report to the functions that changed since a git revision.

  A function counts as changed when any line of one of its clauses or `@spec`s
  was added or modified, or when its file is new and not tracked yet. This turns
  a suite-wide report into a review of a pull request:

      ExUnit.start(
        formatters: [ExUnit.CLIFormatter, Bylaw.Contract.ExUnitFormatter],
        bylaw_contract: [since: "origin/main"]
      )
  """

  alias Bylaw.Contract.Report

  @type changes :: %{optional(Path.t()) => :all | list(Range.t())}

  @doc """
  Removes the missed properties of functions that did not change since the
  revision.

  Options: `:since` (a git revision, required) and `:cd` (the directory to run
  git in, default the current directory).
  """
  @spec filter(report :: Report.t(), options :: list({:since, String.t()} | {:cd, Path.t()})) ::
          Report.t()
  def filter(%Report{} = report, options) do
    since = Keyword.fetch!(options, :since)
    directory = Keyword.get(options, :cd, File.cwd!())
    changes = changes(since, directory)

    properties =
      report.properties
      |> Enum.group_by(&{&1.file, &1.function, &1.arity})
      |> Enum.flat_map(fn {{file, function, arity}, properties} ->
        if touched?(file, function, arity, properties, changes) do
          properties
        else
          Enum.reject(properties, &(&1.status == :missed))
        end
      end)

    %Report{report | properties: properties}
  end

  defp touched?(file, function, arity, properties, changes) do
    case Map.get(changes, file) do
      nil -> false
      :all -> true
      ranges -> function_changed?(file, function, arity, properties, ranges)
    end
  end

  defp function_changed?(file, function, arity, properties, ranges) do
    extents = extents(file, function, arity) ++ Enum.map(properties, &{&1.line, &1.line})

    Enum.any?(extents, fn {first, last} ->
      Enum.any?(ranges, &(not Range.disjoint?(&1, first..last//1)))
    end)
  end

  defp changes(since, directory) do
    diff = git!(directory, ["diff", "--unified=0", "--no-color", "--relative", since, "--"])
    untracked = git!(directory, ["ls-files", "--others", "--exclude-standard"])

    diff
    |> parse_diff(directory)
    |> Map.merge(
      Map.new(String.split(untracked, "\n", trim: true), &{Path.expand(&1, directory), :all})
    )
  end

  defp git!(directory, arguments) do
    case System.cmd("git", arguments,
           cd: directory,
           stderr_to_stdout: true,
           env: [{"GIT_DIR", nil}, {"GIT_WORK_TREE", nil}, {"GIT_INDEX_FILE", nil}]
         ) do
      {output, 0} -> output
      {output, _status} -> raise ArgumentError, "git #{Enum.join(arguments, " ")}: #{output}"
    end
  end

  defp parse_diff(diff, directory) do
    diff
    |> String.split("\n")
    |> Enum.reduce({nil, %{}}, fn line, {file, changes} ->
      cond do
        String.starts_with?(line, "+++ b/") ->
          {Path.expand(String.replace_prefix(line, "+++ b/", ""), directory), changes}

        String.starts_with?(line, "+++ ") ->
          {nil, changes}

        file != nil and String.starts_with?(line, "@@") ->
          {file, Map.update(changes, file, [hunk_range(line)], &[hunk_range(line) | &1])}

        true ->
          {file, changes}
      end
    end)
    |> elem(1)
  end

  defp hunk_range(line) do
    [_all, start, count] = pad_count(Regex.run(~r/\+(\d+)(?:,(\d+))?/, line))
    first = String.to_integer(start)

    case String.to_integer(count) do
      0 -> first..(first + 1)//1
      count -> first..(first + count - 1)//1
    end
  end

  defp pad_count([all, start]), do: [all, start, "1"]
  defp pad_count(match), do: match

  defp extents(file, function, arity) do
    with {:ok, source} <- File.read(file),
         {:ok, ast} <- Code.string_to_quoted(source, token_metadata: true) do
      {_ast, extents} =
        Macro.prewalk(ast, [], fn node, extents ->
          case declaration(node) do
            {^function, ^arity} -> {node, [extent(node) | extents]}
            _other -> {node, extents}
          end
        end)

      extents
    else
      _unreadable -> []
    end
  end

  defp declaration({definition, _meta, [head | _rest]})
       when definition in [:def, :defp, :defmacro, :defmacrop],
       do: head_name(head)

  defp declaration({:@, _meta, [{:spec, _spec_meta, [{:"::", _type_meta, [head | _rest]}]}]}),
    do: head_name(head)

  defp declaration(_node), do: nil

  defp head_name({:when, _meta, [head | _guards]}), do: head_name(head)

  defp head_name({name, _meta, arguments}) when is_atom(name) and is_list(arguments),
    do: {name, Enum.count(arguments)}

  defp head_name(_head), do: nil

  defp extent(node) do
    {_node, lines} =
      Macro.prewalk(node, [], fn
        {_form, meta, _arguments} = node, lines when is_list(meta) ->
          {node, meta_lines(meta) ++ lines}

        node, lines ->
          {node, lines}
      end)

    Enum.min_max(lines)
  end

  defp meta_lines(meta) do
    [meta[:line], get_in(meta, [:end, :line]), get_in(meta, [:closing, :line])]
    |> Enum.filter(&is_integer/1)
  end
end
