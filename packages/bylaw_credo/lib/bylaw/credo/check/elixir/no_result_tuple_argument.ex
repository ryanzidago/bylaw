defmodule Bylaw.Credo.Check.Elixir.NoResultTupleArgument do
  @moduledoc """
  Prevents functions from accepting `{:ok, _}` or `{:error, _}` as their first
  argument.
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: """
      Branch on tagged result tuples before calling a helper. Functions should
      accept the value or error they actually need, rather than dispatching on
      `{:ok, _}` or `{:error, _}` in the first argument position.
      """,
      params: [
        excluded_paths: "List of paths or regexes to exclude from this check"
      ]
    ]

  @result_tags [:ok, :error]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if ignored_path?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    end
  end

  defp traverse(
         {fun, meta, [{:when, _when_meta, [{_name, _name_meta, params} | _guards]} | _body]} = ast,
         issues,
         issue_meta
       )
       when fun in [:def, :defp] and is_list(params) do
    {ast, maybe_add_issue(List.first(params), issues, issue_meta, meta)}
  end

  defp traverse(
         {fun, meta, [{_name, _name_meta, params} | _body]} = ast,
         issues,
         issue_meta
       )
       when fun in [:def, :defp] and is_list(params) do
    {ast, maybe_add_issue(List.first(params), issues, issue_meta, meta)}
  end

  defp traverse(ast, issues, _issue_meta), do: {ast, issues}

  defp maybe_add_issue(nil, issues, _issue_meta, _meta), do: issues

  defp maybe_add_issue(param, issues, issue_meta, meta) do
    case find_result_tuple(param) do
      nil ->
        issues

      tuple_pattern ->
        [issue_for(issue_meta, meta[:line] || 0, tuple_pattern) | issues]
    end
  end

  defp find_result_tuple({:=, _meta, [left, right]}) do
    find_result_tuple(left) || find_result_tuple(right)
  end

  defp find_result_tuple({tag, _value} = tuple) when tag in @result_tags, do: tuple

  defp find_result_tuple({:{}, _meta, [tag, _value | _rest]} = tuple) when tag in @result_tags,
    do: tuple

  defp find_result_tuple(_other), do: nil

  defp issue_for(issue_meta, line_no, tuple_pattern) do
    trigger = Macro.to_string(tuple_pattern)

    format_issue(
      issue_meta,
      message:
        "Do not accept `#{trigger}` as the first function argument. Branch on the result " <>
          "earlier with `case` or `with`, then pass the unwrapped value or reason to a " <>
          "dedicated function.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp ignored_path?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &matches_path?(filename, &1))
  end

  defp matches_path?(filename, %Regex{} = regex), do: Regex.match?(regex, filename)
  defp matches_path?(filename, path) when is_binary(path), do: String.contains?(filename, path)
end
