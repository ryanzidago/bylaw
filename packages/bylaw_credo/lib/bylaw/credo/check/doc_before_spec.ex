defmodule Bylaw.Credo.Check.DocBeforeSpec do
  @moduledoc """
  Requires `@doc` to appear before `@spec` for public function definitions.

  ## Examples

  Avoid:

        @spec handle(result :: term()) :: :ok
        @doc "Handles the result."
        def handle(result), do: :ok
  Prefer:

        @doc "Handles the result."
        @spec handle(result :: term()) :: :ok
        def handle(result), do: :ok

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
          {Bylaw.Credo.Check.DocBeforeSpec, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :normal,
    category: :readability,
    explanations: [check: @moduledoc]

  @public_definitions [:def, :defguard, :defmacro]
  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    source_file
    |> Credo.SourceFile.ast()
    |> find_issues(issue_meta)
  end

  defp find_issues({:ok, ast}, issue_meta), do: find_issues(ast, issue_meta)

  defp find_issues(ast, issue_meta) when is_tuple(ast) do
    case Macro.prewalk(ast, [], &traverse(&1, &2, issue_meta)) do
      {_ast, issues} -> Enum.reverse(issues)
    end
  end

  defp find_issues(_ast, _issue_meta), do: []

  defp traverse({:defmodule, _meta, [_name, [do: body]]} = node, issues, issue_meta) do
    {node, issues_for_body(body, issue_meta) ++ issues}
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}

  defp issues_for_body(body, issue_meta) do
    body
    |> body_expressions()
    |> Enum.reduce({[], []}, fn expression, {pending_attrs, issues} ->
      cond do
        attribute?(expression) ->
          {collect_relevant_attribute(expression, pending_attrs), issues}

        public_definition?(expression) ->
          {[], maybe_issue_for(expression, pending_attrs, issue_meta) ++ issues}

        true ->
          {[], issues}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp body_expressions({:__block__, _meta, expressions}), do: expressions
  defp body_expressions(expression), do: [expression]

  defp attribute?({:@, _meta, [{name, _attribute_meta, _value}]}), do: is_atom(name)
  defp attribute?(_expression), do: false

  defp collect_relevant_attribute({:@, meta, [{:doc, _attribute_meta, _value}]}, pending_attrs) do
    [{:doc, meta[:line]} | pending_attrs]
  end

  defp collect_relevant_attribute({:@, meta, [{:spec, _attribute_meta, _value}]}, pending_attrs) do
    [{:spec, meta[:line]} | pending_attrs]
  end

  defp collect_relevant_attribute(_expression, pending_attrs), do: pending_attrs

  defp public_definition?({kind, _meta, _arguments}), do: kind in @public_definitions
  defp public_definition?(_expression), do: false

  defp maybe_issue_for(definition, pending_attrs, issue_meta) do
    attrs = Enum.reverse(pending_attrs)
    doc_line = last_line_for(attrs, :doc)
    spec_line = first_line_for(attrs, :spec)

    if out_of_order?(doc_line, spec_line) do
      [issue_for(issue_meta, definition_name(definition), doc_line)]
    else
      []
    end
  end

  defp out_of_order?(doc_line, spec_line)
       when is_integer(doc_line) and is_integer(spec_line) and doc_line > spec_line,
       do: true

  defp out_of_order?(_doc_line, _spec_line), do: false

  defp first_line_for(attrs, name) do
    Enum.find_value(attrs, fn
      {^name, line} -> line
      _other -> nil
    end)
  end

  defp last_line_for(attrs, name) do
    attrs
    |> Enum.reverse()
    |> first_line_for(name)
  end

  defp definition_name(
         {kind, _meta, [{:when, _when_meta, [{name, _name_meta, _args} | _guards]} | _rest]}
       )
       when kind in @public_definitions do
    name
  end

  defp definition_name({kind, _meta, [{name, _name_meta, _args} | _rest]})
       when kind in @public_definitions do
    name
  end

  defp issue_for(issue_meta, name, line_no) do
    format_issue(
      issue_meta,
      message:
        "`@doc` should appear before `@spec` so public APIs read as doc, then spec, then function.",
      trigger: Atom.to_string(name),
      line_no: line_no
    )
  end
end
