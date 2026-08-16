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

  @literal_location_marker :bylaw_literal_location

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    literal_locations = literal_locations(source_file)

    source_file
    |> Credo.SourceFile.ast()
    |> collect_issues(issue_meta, literal_locations)
  end

  defp collect_issues({:ok, ast}, issue_meta, literal_locations),
    do: elem(collect_issues(ast, [], issue_meta, literal_locations), 0)

  defp collect_issues(ast, issue_meta, literal_locations) when is_tuple(ast),
    do: elem(collect_issues(ast, [], issue_meta, literal_locations), 0)

  defp collect_issues(_error, _issue_meta, _literal_locations), do: []

  defp collect_issues(ast, issues, issue_meta, literal_locations) do
    case tagged_tuple_values(ast) do
      {:ok, values} ->
        {source_location, literal_locations} =
          take_literal_location(ast, literal_locations)

        {maybe_add_issue(ast, values, issues, issue_meta, source_location), literal_locations}

      :error ->
        collect_child_issues(ast, issues, issue_meta, literal_locations)
    end
  end

  defp collect_child_issues({_form, meta, arguments}, issues, issue_meta, literal_locations)
       when is_list(meta) and is_list(arguments) do
    collect_issues(arguments, issues, issue_meta, literal_locations)
  end

  defp collect_child_issues(values, issues, issue_meta, literal_locations) when is_list(values) do
    if Keyword.keyword?(values) do
      Enum.reduce(values, {issues, literal_locations}, fn {_key, value},
                                                          {issues, literal_locations} ->
        collect_issues(value, issues, issue_meta, literal_locations)
      end)
    else
      Enum.reduce(values, {issues, literal_locations}, fn value, {issues, literal_locations} ->
        collect_issues(value, issues, issue_meta, literal_locations)
      end)
    end
  end

  defp collect_child_issues(value, issues, issue_meta, literal_locations)
       when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> collect_issues(issues, issue_meta, literal_locations)
  end

  defp collect_child_issues(_value, issues, _issue_meta, literal_locations),
    do: {issues, literal_locations}

  defp maybe_add_issue(ast, values, issues, issue_meta, source_location) do
    if Enum.all?(values, &simple_value?/1) do
      issues
    else
      [issue_for(issue_meta, ast, source_location) | issues]
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

  defp issue_for(issue_meta, ast, source_location) do
    {line_no, column, trigger} = source_location(ast, issue_meta, source_location)

    format_issue(
      issue_meta,
      message: "Bind complex expressions to variables before placing them in a tagged tuple.",
      trigger: trigger,
      line_no: line_no,
      column: column
    )
  end

  defp source_location(ast, issue_meta, literal_location) do
    case line_no(ast) do
      0 -> literal_source_location(issue_meta, ast, literal_location)
      line_no -> {line_no, nil, Macro.to_string(ast)}
    end
  end

  defp literal_source_location(issue_meta, _ast, %{line: line, column: column} = location) do
    source_file = IssueMeta.source_file(issue_meta)
    trigger = source_trigger(source_file, location)

    {line, column, trigger}
  end

  defp literal_source_location(_issue_meta, ast, nil),
    do: {nil, nil, Macro.to_string(ast)}

  defp source_trigger(source_file, %{line: line, column: column, closing: closing}) do
    source_line =
      source_file
      |> Credo.SourceFile.lines()
      |> Enum.at(line - 1)
      |> elem(1)

    source_from_column = String.slice(source_line, (column - 1)..-1//1)

    case closing do
      [line: ^line, column: closing_column] ->
        String.slice(source_from_column, 0, closing_column - column + 1)

      _other ->
        String.trim_trailing(source_from_column)
    end
  end

  defp take_literal_location(ast, literal_locations) do
    if line_no(ast) == 0 do
      pop_literal_location(literal_locations, ast)
    else
      {nil, literal_locations}
    end
  end

  defp pop_literal_location(literal_locations, ast) do
    case Map.get(literal_locations, ast, []) do
      [location | remaining] ->
        {location, Map.put(literal_locations, ast, remaining)}

      [] ->
        {nil, literal_locations}
    end
  end

  defp literal_locations(source_file) do
    source = Credo.SourceFile.source(source_file)

    case Code.string_to_quoted(source, literal_parser_options(source_file)) do
      {:ok, ast} ->
        ast
        |> collect_literal_locations([])
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {literal, locations} ->
          {literal, Enum.sort_by(locations, &{&1.line, &1.column})}
        end)

      _error ->
        %{}
    end
  end

  defp literal_parser_options(source_file) do
    [
      line: 1,
      columns: true,
      file: source_file.filename,
      emit_warnings: false,
      token_metadata: true,
      literal_encoder: &encode_literal_location/2
    ]
  end

  defp encode_literal_location(literal, meta) do
    {:ok, {:__block__, Keyword.put(meta, @literal_location_marker, true), [literal]}}
  end

  defp collect_literal_locations(
         {:__block__, meta, [literal]},
         locations
       )
       when is_list(meta) do
    locations =
      if meta[@literal_location_marker] do
        decoded_literal = decode_literal_locations(literal)

        case tagged_tuple_values(decoded_literal) do
          {:ok, _values} ->
            location = %{line: meta[:line], column: meta[:column], closing: meta[:closing]}
            [{decoded_literal, location} | locations]

          :error ->
            locations
        end
      else
        locations
      end

    collect_literal_locations(literal, locations)
  end

  defp collect_literal_locations(value, locations) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> collect_literal_locations(locations)
  end

  defp collect_literal_locations(values, locations) when is_list(values) do
    Enum.reduce(values, locations, &collect_literal_locations/2)
  end

  defp collect_literal_locations(_value, locations), do: locations

  defp decode_literal_locations({:__block__, meta, [literal]}) when is_list(meta) do
    if meta[@literal_location_marker] do
      decode_literal_locations(literal)
    else
      {:__block__, meta, [decode_literal_locations(literal)]}
    end
  end

  defp decode_literal_locations(value) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> Enum.map(&decode_literal_locations/1)
    |> List.to_tuple()
  end

  defp decode_literal_locations(values) when is_list(values),
    do: Enum.map(values, &decode_literal_locations/1)

  defp decode_literal_locations(value), do: value

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
