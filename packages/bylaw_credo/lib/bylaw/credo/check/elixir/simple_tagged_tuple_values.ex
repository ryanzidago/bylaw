defmodule Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues do
  @moduledoc """
  Requires tagged tuples to contain only simple values.

  ## Examples

  Avoid:

      {:ok, build_result()}
      {:reply, %{status: :ready}, state}
      {:cont, {:ok, %{acc | committed: [entry | acc.committed]}}}

  Prefer:

      result = build_result()
      {:ok, result}

      reply = %{status: :ready}
      {:reply, reply, state}

      acc = %{acc | committed: [entry | acc.committed]}
      {:cont, {:ok, acc}}


  Scalar literals and variables are simple values. Tagged tuples may be nested
  recursively when all of their leaf values are scalar literals or variables.

  Maps, structs, lists, untagged tuples, field access, function calls,
  pipelines, string interpolation, and operators should be bound to variables
  before they are placed in a tagged tuple.

  ## Options

  This check has no check-specific options. Configure it with an empty option
  list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.SimpleTaggedTupleValues, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    tags: [:readability],
    explanations: [
      check: @moduledoc
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.SourceFile.ast()
    |> collect_issues(issue_meta)
  end

  defp collect_issues({:ok, ast}, issue_meta), do: collect_issues(ast, [], issue_meta)
  defp collect_issues(ast, issue_meta) when is_tuple(ast), do: collect_issues(ast, [], issue_meta)
  defp collect_issues(_error, _issue_meta), do: []

  defp collect_issues(ast, issues, issue_meta) do
    case tagged_tuple_values(ast) do
      {:ok, values} ->
        maybe_add_issue(ast, values, issues, issue_meta)

      :error ->
        collect_child_issues(ast, issues, issue_meta)
    end
  end

  defp collect_child_issues({_form, meta, arguments}, issues, issue_meta)
       when is_list(meta) and is_list(arguments) do
    collect_issues(arguments, issues, issue_meta)
  end

  defp collect_child_issues(values, issues, issue_meta) when is_list(values) do
    if Keyword.keyword?(values) do
      Enum.reduce(values, issues, fn {_key, value}, acc ->
        collect_issues(value, acc, issue_meta)
      end)
    else
      Enum.reduce(values, issues, &collect_issues(&1, &2, issue_meta))
    end
  end

  defp collect_child_issues(value, issues, issue_meta) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> collect_issues(issues, issue_meta)
  end

  defp collect_child_issues(_value, issues, _issue_meta), do: issues

  defp maybe_add_issue(ast, values, issues, issue_meta) do
    if Enum.all?(values, &simple_value?/1) do
      issues
    else
      [issue_for(issue_meta, ast) | issues]
    end
  end

  defp simple_value?(value)
       when is_atom(value) or is_integer(value) or is_float(value) or is_binary(value),
       do: true

  defp simple_value?({:-, meta, [value]})
       when is_list(meta) and (is_integer(value) or is_float(value)),
       do: true

  defp simple_value?({name, meta, context})
       when is_atom(name) and is_list(meta) and (is_atom(context) or is_nil(context)),
       do: true

  defp simple_value?(value) do
    case tagged_tuple_values(value) do
      {:ok, values} -> Enum.all?(values, &simple_value?/1)
      :error -> false
    end
  end

  defp tagged_tuple_values({tag, value}) when is_atom(tag), do: {:ok, [value]}

  defp tagged_tuple_values({:{}, _meta, [tag, value | values]}) when is_atom(tag),
    do: {:ok, [value | values]}

  defp tagged_tuple_values(_value), do: :error

  defp issue_for(issue_meta, ast) do
    trigger = Macro.to_string(ast)
    {line_no, column} = source_location(ast, issue_meta, trigger)

    format_issue(
      issue_meta,
      message: "Bind complex expressions to variables before placing them in a tagged tuple.",
      trigger: trigger,
      line_no: line_no,
      column: column
    )
  end

  defp source_location(ast, issue_meta, trigger) do
    case line_no(ast) do
      0 -> find_source_location(issue_meta, trigger)
      line_no -> {line_no, nil}
    end
  end

  defp find_source_location(issue_meta, trigger) do
    issue_meta
    |> IssueMeta.source_file()
    |> Credo.SourceFile.lines()
    |> Enum.find_value({0, nil}, fn {line_no, line} ->
      case :binary.match(line, trigger) do
        {column, _length} -> {line_no, column + 1}
        :nomatch -> nil
      end
    end)
  end

  defp line_no({_tag, {_name, meta, _arguments}}) when is_list(meta), do: meta[:line] || 0
  defp line_no({:{}, meta, _values}) when is_list(meta), do: meta[:line] || 0

  defp line_no(ast) do
    {_ast, line_no} =
      Macro.prewalk(ast, 0, fn
        {_form, meta, _arguments} = node, 0 when is_list(meta) ->
          {node, meta[:line] || 0}

        node, line_no ->
          {node, line_no}
      end)

    line_no
  end
end
