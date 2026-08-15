defmodule Bylaw.Credo.Check.PhoenixLiveView.RequireFunctionComponentAttrs do
  @moduledoc """
  Requires caller-facing assigns in HEEx function components to have `attr` or
  `slot` declarations.

  ## Examples

  Avoid:

      defp summary_card(assigns) do
        ~H\"\"\"
        <h2>{@title}</h2>
        \"\"\"
      end

  Prefer:

      attr :title, :string, required: true

      defp summary_card(assigns) do
        ~H\"\"\"
        <h2>{@title}</h2>
        \"\"\"
      end

  `render/1` is excluded because a LiveView's page assigns belong to its
  lifecycle rather than a function-component contract. Assigns established
  internally with `assign/2,3` are also excluded. `assign_new/3` does not
  replace a declaration for a caller-facing input.


  This check treats public and private arity-one functions with a terminal
  `~H` return as function components. It uses static AST and HEEx token
  analysis and requires `phoenix_live_view` to be available.

  Declarations make a component's public inputs explicit, enable compile-time
  validation and useful warnings, and give callers documentation at the point
  where the component is defined. Without them, misspelled or missing assigns
  fail later in rendering and the component's contract stays implicit.
  ## Options

  This check has no check-specific options. Configure it with an empty option
  list.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  {Bylaw.Credo.Check.PhoenixLiveView.RequireFunctionComponentAttrs, []}
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:web],
    explanations: [check: @moduledoc]

  alias Bylaw.Credo.Heex

  @definitions [:def, :defp, :defmacro, :defmacrop]

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
    {_ast, issues} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [_name, [do: body]]} = node, issues ->
          {node, issues_for_module(body, issue_meta) ++ issues}

        node, issues ->
          {node, issues}
      end)

    Enum.sort_by(issues, &{&1.line_no, &1.column || 0})
  end

  defp find_issues(_ast, _issue_meta), do: []

  defp issues_for_module(body, issue_meta) do
    body
    |> body_expressions()
    |> Enum.reduce(%{pending: declarations(), components: %{}, order: []}, &collect_expression/2)
    |> issues_for_components(issue_meta)
  end

  defp collect_expression({:attr, _meta, [name | _rest]}, state) when is_atom(name) do
    put_in(state.pending.attrs, MapSet.put(state.pending.attrs, name))
  end

  defp collect_expression({:slot, _meta, [name | _rest]}, state) when is_atom(name) do
    put_in(state.pending.slots, MapSet.put(state.pending.slots, name))
  end

  defp collect_expression({kind, _meta, _arguments} = definition, state)
       when kind in @definitions do
    state = collect_definition(definition, state)
    %{state | pending: declarations()}
  end

  defp collect_expression(_expression, state), do: state

  defp collect_definition({kind, _meta, arguments} = definition, state)
       when kind in [:def, :defp] do
    case definition_identity(arguments) do
      {name, arity} ->
        key = {name, arity}
        component = Map.get(state.components, key, %{declarations: declarations(), clauses: []})

        component = %{
          declarations: merge_declarations(component.declarations, state.pending),
          clauses: [definition | component.clauses]
        }

        order =
          if Map.has_key?(state.components, key) do
            state.order
          else
            [key | state.order]
          end

        %{state | components: Map.put(state.components, key, component), order: order}

      nil ->
        state
    end
  end

  defp collect_definition(_definition, state), do: state

  defp issues_for_components(state, issue_meta) do
    state.order
    |> Enum.reverse()
    |> Enum.flat_map(fn {name, arity} = key ->
      component = Map.fetch!(state.components, key)

      if name == :render and arity == 1 do
        []
      else
        issues_for_component(name, arity, component, issue_meta)
      end
    end)
  end

  defp issues_for_component(name, 1, component, issue_meta) do
    references =
      component.clauses
      |> Enum.reverse()
      |> Enum.flat_map(&templates_for_definition/1)
      |> Enum.flat_map(fn {template, internal_assigns} ->
        template
        |> references()
        |> Enum.reject(&MapSet.member?(internal_assigns, &1.name))
      end)
      |> first_references()

    Enum.flat_map(references, fn reference ->
      if declared?(reference, component.declarations) do
        []
      else
        [issue_for(issue_meta, name, reference)]
      end
    end)
  end

  defp issues_for_component(_name, _arity, _component, _issue_meta), do: []

  defp templates_for_definition({_kind, _meta, [_head, body_options]}) do
    body_options
    |> Keyword.get(:do)
    |> terminal_templates(MapSet.new())
  end

  defp templates_for_definition({_kind, _meta, [_head]}), do: []

  defp terminal_templates({:sigil_H, _meta, _arguments} = sigil, internal_assigns) do
    case Heex.template(sigil) do
      %Heex.Template{} = template -> [{template, internal_assigns}]
      nil -> []
    end
  end

  defp terminal_templates({:__block__, _meta, expressions}, internal_assigns) do
    {prefix, terminal} = split_terminal(expressions)
    internal_assigns = Enum.reduce(prefix, internal_assigns, &collect_internal_assigns/2)
    terminal_templates(terminal, internal_assigns)
  end

  defp terminal_templates({kind, _meta, [_condition, options]}, internal_assigns)
       when kind in [:if, :unless] do
    options
    |> Keyword.take([:do, :else])
    |> Keyword.values()
    |> Enum.flat_map(&terminal_templates(&1, internal_assigns))
  end

  defp terminal_templates({:case, _meta, [_subject, [do: clauses]]}, internal_assigns) do
    terminal_clause_templates(clauses, internal_assigns)
  end

  defp terminal_templates({:with, _meta, arguments}, internal_assigns) do
    arguments
    |> List.last()
    |> Keyword.take([:do, :else])
    |> Keyword.values()
    |> Enum.flat_map(fn
      clauses when is_list(clauses) -> terminal_clause_templates(clauses, internal_assigns)
      expression -> terminal_templates(expression, internal_assigns)
    end)
  end

  defp terminal_templates({:cond, _meta, [[do: clauses]]}, internal_assigns) do
    terminal_clause_templates(clauses, internal_assigns)
  end

  defp terminal_templates(_expression, _internal_assigns), do: []

  defp terminal_clause_templates(clauses, internal_assigns) do
    Enum.flat_map(clauses, fn
      {:->, _meta, [_patterns, body]} -> terminal_templates(body, internal_assigns)
      _clause -> []
    end)
  end

  defp collect_internal_assigns(
         {:=, _meta, [{:assigns, _variable_meta, context}, right]},
         internal_assigns
       )
       when is_atom(context) or is_nil(context) do
    right
    |> assign_keys()
    |> Enum.reduce(internal_assigns, &MapSet.put(&2, &1))
  end

  defp collect_internal_assigns(_expression, internal_assigns), do: internal_assigns

  defp assign_keys(ast) do
    {_ast, keys} =
      Macro.prewalk(ast, [], fn
        {name, _meta, arguments} = node, keys when name == :assign and is_list(arguments) ->
          {node, literal_assign_keys(arguments) ++ keys}

        {{:., _dot_meta, [_module, :assign]}, _meta, arguments} = node, keys
        when is_list(arguments) ->
          {node, literal_assign_keys(arguments) ++ keys}

        node, keys ->
          {node, keys}
      end)

    MapSet.new(keys)
  end

  defp literal_assign_keys(arguments) do
    case arguments do
      [key, _value] when is_atom(key) -> [key]
      [_assigns, key, _value] when is_atom(key) -> [key]
      [values] when is_list(values) -> Keyword.keys(values)
      [_assigns, values] when is_list(values) -> Keyword.keys(values)
      [{:%{}, _meta, values}] -> Keyword.keys(values)
      [_assigns, {:%{}, _meta, values}] -> Keyword.keys(values)
      _arguments -> []
    end
  end

  defp references(template) do
    template
    |> Heex.tokens()
    |> Enum.flat_map(&references_in_token/1)
  end

  defp references_in_token(%Heex.Expression{} = expression) do
    references_in_expression(expression.source, expression.line, expression.column, 0)
  end

  defp references_in_token(%Heex.Tag{} = tag) do
    Enum.flat_map(tag.attrs, fn
      %{value: {:expr, source, meta}} = attr ->
        references_in_expression(
          source,
          meta[:line] || attr.line || tag.line,
          meta[:column] || attr.column || tag.column,
          -1
        )

      _attr ->
        []
    end)
  end

  defp references_in_token(_token), do: []

  defp references_in_expression(source, line, column, column_adjustment) do
    case Code.string_to_quoted(source, columns: true) do
      {:ok, ast} ->
        slot_names = rendered_slot_names(ast)

        {_ast, references} =
          Macro.prewalk(ast, [], fn
            {:@, meta, [{name, _name_meta, context}]} = node, references
            when is_atom(name) and (is_atom(context) or is_nil(context)) ->
              reference = %{
                name: name,
                line: line + (meta[:line] || 1) - 1,
                column: column + (meta[:column] || 1) + column_adjustment,
                slot?: name in slot_names
              }

              {node, [reference | references]}

            node, references ->
              {node, references}
          end)

        Enum.reverse(references)

      _error ->
        []
    end
  end

  defp rendered_slot_names(ast) do
    {_ast, names} =
      Macro.prewalk(ast, [], fn
        {:render_slot, _meta, [{:@, _at_meta, [{name, _name_meta, _context}]} | _rest]} = node,
        names
        when is_atom(name) ->
          {node, [name | names]}

        node, names ->
          {node, names}
      end)

    names
  end

  defp first_references(references) do
    references
    |> Enum.reduce(%{}, fn reference, found ->
      Map.update(found, reference.name, reference, fn existing ->
        %{existing | slot?: existing.slot? or reference.slot?}
      end)
    end)
    |> Map.values()
    |> Enum.sort_by(&{&1.line, &1.column})
  end

  defp declared?(%{name: name, slot?: true}, declarations) do
    MapSet.member?(declarations.slots, name)
  end

  defp declared?(%{name: name}, declarations) do
    MapSet.member?(declarations.attrs, name) or MapSet.member?(declarations.slots, name)
  end

  defp issue_for(issue_meta, component_name, reference) do
    declaration =
      if reference.slot? do
        "a `slot :#{reference.name}` declaration"
      else
        "an `attr :#{reference.name}` or `slot :#{reference.name}` declaration"
      end

    action =
      if reference.slot? do
        "renders"
      else
        "uses caller-facing assign"
      end

    format_issue(
      issue_meta,
      message:
        "Function component `#{component_name}/1` #{action} `@#{reference.name}` without #{declaration}.",
      trigger: "@#{reference.name}",
      line_no: reference.line,
      column: reference.column
    )
  end

  defp definition_identity([head | _body]) do
    case head do
      {:when, _meta, [call | _guards]} -> call_identity(call)
      call -> call_identity(call)
    end
  end

  defp call_identity({name, _meta, arguments}) when is_atom(name) do
    {name, Enum.count(arguments || [])}
  end

  defp call_identity(_head), do: nil

  defp declarations, do: %{attrs: MapSet.new(), slots: MapSet.new()}

  defp merge_declarations(left, right) do
    %{
      attrs: MapSet.union(left.attrs, right.attrs),
      slots: MapSet.union(left.slots, right.slots)
    }
  end

  defp body_expressions({:__block__, _meta, expressions}), do: expressions
  defp body_expressions(expression), do: [expression]

  defp split_terminal(expressions) do
    {Enum.drop(expressions, -1), List.last(expressions)}
  end
end
