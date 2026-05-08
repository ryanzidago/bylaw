defmodule Bylaw.Credo.Check.NamedSpecParams do
  @moduledoc """
  Requires named parameters in all `@spec` declarations.

  ## Avoid

  Positional-only types omit what each argument represents:

      @spec fetch(UUIDv7.t(), integer()) :: {:ok, Run.t()} | {:error, term()}
      @spec submit(UUIDv7.t(), UUIDv7.t(), UUIDv7.t(), UUIDv7.t(), list(map())) :: :ok

  ## Prefer

  Give each parameter a name so the spec is self-documenting:

      @spec fetch(run_id :: UUIDv7.t(), limit :: integer()) :: {:ok, Run.t()} | {:error, term()}
      @spec submit(
              tenant_id :: UUIDv7.t(),
              workspace_id :: UUIDv7.t(),
              run_id :: UUIDv7.t(),
              message_id :: UUIDv7.t(),
              tool_results :: list(map())
            ) :: :ok
  """

  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    param_defaults: [min_params: 1],
    explanations: [
      check: @moduledoc,
      params: [
        min_params: "Minimum number of parameters to trigger the check (default: 1)."
      ]
    ]

  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    min_params = Params.get(params, :min_params, __MODULE__)

    source_file
    |> Credo.SourceFile.ast()
    |> find_issues(issue_meta, min_params)
  end

  defp find_issues({:ok, ast}, issue_meta, min_params) do
    case Macro.prewalk(ast, [], &traverse(&1, &2, issue_meta, min_params)) do
      {_ast, issues} -> issues
    end
  end

  defp find_issues(ast, issue_meta, min_params) when is_tuple(ast) do
    case Macro.prewalk(ast, [], &traverse(&1, &2, issue_meta, min_params)) do
      {_ast, issues} -> issues
    end
  end

  defp find_issues(_error, _issue_meta, _min_params), do: []

  # @spec fun_name(args...) :: return_type
  defp traverse(
         {:@, _meta, [{:spec, _spec_meta, [spec_definition]}]} = node,
         issues,
         issue_meta,
         min_params
       ) do
    args = extract_args(spec_definition)

    if Enum.count(args) >= min_params and not all_named?(args) do
      line = spec_line(spec_definition)
      {node, [issue_for(issue_meta, line) | issues]}
    else
      {node, issues}
    end
  end

  defp traverse(node, issues, _issue_meta, _min_params), do: {node, issues}

  # @spec fun(args) :: ret when constraints
  defp extract_args(
         {:when, _when_meta,
          [{:"::", _op_meta, [{_fun_name, _fun_meta, args} | _rest]} | _when_clauses]}
       )
       when is_list(args) do
    args
  end

  # @spec fun(args) :: ret
  defp extract_args({:"::", _op_meta, [{_fun_name, _fun_meta, args} | _rest]})
       when is_list(args) do
    args
  end

  defp extract_args(_other), do: []

  defp all_named?(args) do
    Enum.all?(args, fn
      {:"::", _meta, _parts} -> true
      _other -> false
    end)
  end

  defp spec_line({:when, _when_meta, [{:"::", meta, _parts} | _clauses]}), do: meta[:line]
  defp spec_line({:"::", meta, _parts}), do: meta[:line]
  defp spec_line(_other), do: 0

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message: "Spec parameters should use named types (e.g., `tenant_id :: UUIDv7.t()`).",
      trigger: "@spec",
      line_no: line_no
    )
  end
end
