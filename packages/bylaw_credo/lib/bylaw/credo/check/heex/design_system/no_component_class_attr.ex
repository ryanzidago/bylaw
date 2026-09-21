defmodule Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassAttr do
  @moduledoc """
  Forbids class attributes in the declarations of HEEx function components.

  ## Examples

  Avoid:

      attr :class, :any, default: nil
      attr :wrapper_class, :string, default: nil

      def button(assigns) do
        ~H\"\"\"
        <button class={@class}>{render_slot(@inner_block)}</button>
        \"\"\"
      end

  Prefer:

      attr :size, :string, values: ~w(md lg), default: "md"

      def button(assigns) do
        ~H\"\"\"
        <button class={size_class(@size)}>{render_slot(@inner_block)}</button>
        \"\"\"
      end

  A component that declares a class attribute has no styling contract. Every caller
  can restyle it, and the component cannot tell which of its own classes a caller
  meant to replace. Props such as `size`, `variant` or `position` name the choices
  the component supports and keep its markup in one place.

  Attribute names ending in `_class` are reported too, since renaming the attribute
  keeps the pass-through and only hides it. Declaring the attribute is also the one
  choice a component gets: `class` is one of Phoenix's global attributes, so a
  component that declares `attr :rest, :global` cannot refuse a class at runtime.
  Components whose class attribute is their documented interface, such as an icon
  that is nothing but a class, belong in `:excluded_components`. Its call-site
  counterpart is `Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClass`.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassAttr,
           [
             excluded_components: [".icon", ".input"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:excluded_components` - Component names whose class attribute is allowed, written as they appear in markup, with an optional leading dot (default: none).

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.HEEx.DesignSystem.NoComponentClassAttr, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    tags: [:web, :design_system],
    param_defaults: [excluded_components: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_components:
          "Component names whose class attribute is allowed, written as they appear in markup, with an optional leading dot (default: none)."
      ]
    ]

  @message "Give the component a named prop instead of a class attribute, so it owns its own styling."
  @definitions [:def, :defp]

  @doc false
  @spec run(Credo.SourceFile.t(), list()) :: list(Credo.Issue.t())
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    excluded_components =
      params
      |> Params.get(:excluded_components, __MODULE__)
      |> MapSet.new(&component_name/1)

    source_file
    |> Credo.SourceFile.ast()
    |> class_attrs()
    |> Enum.reject(&MapSet.member?(excluded_components, &1.component))
    |> Enum.sort_by(& &1.line)
    |> Enum.map(&issue_for(issue_meta, source_file, &1))
  end

  defp class_attrs({:ok, ast}), do: class_attrs(ast)

  defp class_attrs(ast) when is_tuple(ast) do
    {_ast, attrs} =
      Macro.prewalk(ast, [], fn
        {:defmodule, _meta, [_name, [do: body]]} = node, attrs ->
          {node, attrs_in_module(body) ++ attrs}

        node, attrs ->
          {node, attrs}
      end)

    attrs
  end

  defp class_attrs(_ast), do: []

  # `attr` declarations belong to the definition that follows them, which is what names
  # the component an exclusion or a message refers to.
  defp attrs_in_module(body) do
    {pending, attrs} =
      body
      |> body_expressions()
      |> Enum.reduce({[], []}, &collect_expression/2)

    attrs ++ pending
  end

  defp collect_expression({:attr, meta, [name | _rest]}, {pending, attrs}) when is_atom(name) do
    if class_attr?(name) do
      {[attr(name, meta) | pending], attrs}
    else
      {pending, attrs}
    end
  end

  defp collect_expression({kind, _meta, arguments}, {pending, attrs}) when kind in @definitions do
    {[], named(pending, component_name(arguments)) ++ attrs}
  end

  defp collect_expression(_expression, acc), do: acc

  defp attr(name, meta) do
    %{name: Atom.to_string(name), component: nil, line: meta[:line]}
  end

  defp named(attrs, component) do
    Enum.map(attrs, &%{&1 | component: component})
  end

  defp class_attr?(name) do
    name == :class or
      name
      |> Atom.to_string()
      |> String.ends_with?("_class")
  end

  defp component_name([head | _body]) do
    case head do
      {:when, _meta, [call | _guards]} -> call_name(call)
      call -> call_name(call)
    end
  end

  defp component_name("." <> name) when is_binary(name), do: name
  defp component_name(name) when is_binary(name), do: name

  defp call_name({name, _meta, _arguments}) when is_atom(name), do: Atom.to_string(name)
  defp call_name(_call), do: nil

  defp body_expressions({:__block__, _meta, expressions}), do: expressions
  defp body_expressions(expression), do: [expression]

  defp issue_for(issue_meta, source_file, attr) do
    format_issue(
      issue_meta,
      message: message_for(attr.component),
      trigger: attr.name,
      line_no: attr.line,
      column: name_column(source_file, attr)
    )
  end

  # The declaration's own column points at `attr`; point at the name it declares instead.
  defp name_column(source_file, %{line: line, name: name}) when is_integer(line) do
    declaration = Credo.SourceFile.line_at(source_file, line)

    case :binary.match(declaration, ":" <> name) do
      {index, _length} -> index + 2
      :nomatch -> nil
    end
  end

  defp name_column(_source_file, _attr), do: nil

  defp message_for(nil), do: @message
  defp message_for(component), do: "#{@message} Component: <.#{component}>."
end
