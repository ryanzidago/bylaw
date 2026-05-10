defmodule Bylaw.Credo.Check.Ecto.ComposablePreloadQueries do
  @moduledoc """
  Query helpers named `*_preload_query` should not hard-code their own
  Ecto preload expression. Accept a `preloads:` option, bind it to a local
  `preloads` variable, and pass it to Ecto with `preload(^preloads)`.

  ## Examples

  Avoid:

        defp input_file_preload_query do
          ToolCallFile
          |> from(as: :tool_file)
          |> preload([:file])
        end

  Prefer:

        defp input_file_preload_query(opts) do
          preloads = Keyword.get(opts, :preloads, [])

          ToolCallFile
          |> from(as: :tool_file)
          |> preload(^preloads)
        end

  ## Notes

  This check uses static AST analysis, so it favors clear source-level patterns over runtime behavior.

  ## Options

  This check has no check-specific options. Configure it with an empty option list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.ComposablePreloadQueries, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    explanations: [
      check: @moduledoc
    ]

  alias Credo.SourceFile
  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> SourceFile.ast()
    |> find_issues(issue_meta)
  end

  defp find_issues({:ok, ast}, issue_meta), do: find_issues(ast, issue_meta)

  defp find_issues(ast, issue_meta) when is_tuple(ast) do
    ast
    |> Macro.prewalk([], &traverse_definition(&1, &2, issue_meta))
    |> elem(1)
    |> Enum.reverse()
  end

  defp find_issues(_other, _issue_meta), do: []

  defp traverse_definition({definition, _meta, [head, body]} = node, issues, issue_meta)
       when definition in [:def, :defp] do
    issues =
      if preload_query_function?(head) do
        body = extract_do_body(body)
        opts_preloads? = opts_preloads?(head, body)

        collect_preload_issues(body, issues, issue_meta, opts_preloads?)
      else
        issues
      end

    {node, issues}
  end

  defp traverse_definition(node, issues, _issue_meta), do: {node, issues}

  defp preload_query_function?(head) do
    case function_name(head) do
      nil ->
        false

      name ->
        name
        |> Atom.to_string()
        |> String.ends_with?("_preload_query")
    end
  end

  defp function_name({:when, _meta, [head | _guards]}), do: function_name(head)
  defp function_name({name, _meta, args}) when is_atom(name) and is_list(args), do: name
  defp function_name({name, _meta, nil}) when is_atom(name), do: name
  defp function_name(_other), do: nil

  defp function_args({:when, _meta, [head | _guards]}), do: function_args(head)
  defp function_args({_name, _meta, args}) when is_list(args), do: args
  defp function_args({_name, _meta, nil}), do: []
  defp function_args(_other), do: []

  defp extract_do_body(body) when is_list(body) do
    if Keyword.keyword?(body), do: Keyword.get(body, :do)
  end

  defp extract_do_body(_body), do: nil

  defp opts_preloads?(head, body) do
    opts_argument?(head) and preloads_bound_from_opts?(body)
  end

  defp opts_argument?(head) do
    head
    |> function_args()
    |> Enum.any?(&opts_arg?/1)
  end

  defp opts_arg?({:\\, _meta, [arg, _default]}), do: opts_arg?(arg)
  defp opts_arg?({:opts, _meta, nil}), do: true
  defp opts_arg?(_other), do: false

  defp preloads_bound_from_opts?(nil), do: false

  defp preloads_bound_from_opts?(body) do
    body
    |> Macro.prewalk(false, &traverse_preloads_binding/2)
    |> elem(1)
  end

  defp traverse_preloads_binding(
         {:=, _meta, [{:preloads, _var_meta, nil}, value]} = node,
         bound?
       ) do
    {node, bound? or preloads_from_opts?(value)}
  end

  defp traverse_preloads_binding(node, bound?), do: {node, bound?}

  defp preloads_from_opts?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Keyword]}, :get]}, _call_meta,
          [{:opts, _opts_meta, nil}, :preloads, []]}
       ),
       do: true

  defp preloads_from_opts?(
         {:|>, _pipe_meta,
          [
            {:opts, _opts_meta, nil},
            {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Keyword]}, :get]}, _call_meta,
             [:preloads, []]}
          ]}
       ),
       do: true

  defp preloads_from_opts?(_other), do: false

  defp collect_preload_issues(nil, issues, _issue_meta, _opts_preloads?), do: issues

  defp collect_preload_issues(body, issues, issue_meta, opts_preloads?) do
    body
    |> Macro.prewalk(issues, &traverse_preload(&1, &2, issue_meta, opts_preloads?))
    |> elem(1)
  end

  defp traverse_preload({:preload, meta, args} = node, issues, issue_meta, opts_preloads?)
       when is_list(args) do
    {node, maybe_add_issue(issues, issue_meta, meta, args, "preload", opts_preloads?)}
  end

  defp traverse_preload(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Ecto, :Query]}, :preload]}, meta, args} =
           node,
         issues,
         issue_meta,
         opts_preloads?
       )
       when is_list(args) do
    {node, maybe_add_issue(issues, issue_meta, meta, args, "Ecto.Query.preload", opts_preloads?)}
  end

  defp traverse_preload(node, issues, _issue_meta, _opts_preloads?), do: {node, issues}

  defp maybe_add_issue(issues, _issue_meta, _meta, [], _trigger, _opts_preloads?), do: issues

  defp maybe_add_issue(issues, issue_meta, meta, args, trigger, opts_preloads?) do
    if opts_preloads? and dynamic_preloads?(List.last(args)) do
      issues
    else
      [issue_for(issue_meta, meta, trigger) | issues]
    end
  end

  defp dynamic_preloads?({:^, _pin_meta, [{:preloads, _var_meta, nil}]}), do: true
  defp dynamic_preloads?(_other), do: false

  defp issue_for(issue_meta, meta, trigger) do
    format_issue(
      issue_meta,
      message:
        "Do not hard-code preloads inside `*_preload_query` helpers. Accept `opts`, set " <>
          "`preloads = Keyword.get(opts, :preloads, [])`, call `preload(^preloads)`, " <>
          "and have callers pass `preloads: [...]`.",
      trigger: trigger,
      line_no: meta[:line] || 0
    )
  end
end
