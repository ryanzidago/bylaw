defmodule Bylaw.Credo.Check.Testing.NoDescribeBlocks do
  @moduledoc """
  Avoid `describe` blocks in test files.

  ## Examples

  Avoid:

      describe "creating a user" do
        test "returns the user" do
          assert create_user().active?
        end
      end

  Prefer:

      test "creating a user returns an active user" do
        assert create_user().active?
      end

  ## Notes

  Descriptive standalone test names make each test's behavior visible without
  relying on an enclosing block. When a suite grows, split it into multiple
  focused test files instead of grouping unrelated behavior with `describe`.

  Path exclusions are matched against the source filename and are intended for
  generated files or temporary migration areas.

  The check uses static AST analysis, so dynamic code generation and
  macro-expanded code may fall outside its signal.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoDescribeBlocks,
           [
             excluded_paths: ["test/support/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:excluded_paths` - Paths containing any configured string are skipped.
    Use this for test files that are intentionally being migrated.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoDescribeBlocks, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: """
        Paths containing any configured string are skipped. Use this for test
        files that are intentionally being migrated.
        """
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if test_file?(source_file.filename) and not excluded?(source_file.filename, excluded_paths) do
      issue_meta = IssueMeta.for(source_file, params)

      ignored_describe_lines =
        source_file
        |> local_describe_lines()
        |> MapSet.union(imported_non_ex_unit_describe_lines(source_file))

      context = %{
        aliased_describe_lines: aliased_describe_lines(source_file),
        ignored_describe_lines: ignored_describe_lines
      }

      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta, context))
    else
      []
    end
  end

  defp test_file?(filename) do
    String.ends_with?(filename, "_test.exs")
  end

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &String.contains?(filename, &1))
  end

  defp traverse({:quote, meta, args}, issues, _issue_meta, _aliases) do
    {{:quote, meta, rename_quoted_describes(args)}, issues}
  end

  defp traverse({definition, meta, [head | body]}, issues, _issue_meta, _aliases)
       when definition in [:def, :defp, :defmacro, :defmacrop] do
    {{definition, meta, [rename_describe_definition(head) | body]}, issues}
  end

  defp traverse({:describe, meta, [_name, [do: _body]]} = ast, issues, issue_meta, context) do
    if MapSet.member?(context.ignored_describe_lines, meta[:line]) do
      {ast, issues}
    else
      {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
    end
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:"Elixir", :ExUnit, :Case]}, :describe]},
          meta, [_name, [do: _body]]} = ast,
         issues,
         issue_meta,
         _aliases
       ) do
    {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [_module]}, :describe]}, meta,
          [_name, [do: _body]]} = ast,
         issues,
         issue_meta,
         context
       ) do
    if MapSet.member?(context.aliased_describe_lines, meta[:line]) do
      {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [_module, _nested_module]}, :describe]},
          meta, [_name, [do: _body]]} = ast,
         issues,
         issue_meta,
         context
       ) do
    if MapSet.member?(context.aliased_describe_lines, meta[:line]) do
      {ast, [issue_for(issue_meta, meta[:line] || 0) | issues]}
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _aliases), do: {ast, issues}

  defp aliased_describe_lines(source_file) do
    source_file
    |> Credo.SourceFile.ast()
    |> remove_quoted_code()
    |> collect_scope_describe_lines(%{})
  end

  defp local_describe_lines(source_file) do
    source_file
    |> Credo.SourceFile.ast()
    |> remove_quoted_code()
    |> collect_local_describe_lines()
  end

  defp imported_non_ex_unit_describe_lines(source_file) do
    source_file
    |> Credo.SourceFile.ast()
    |> remove_quoted_code()
    |> collect_imported_describe_lines(false)
  end

  defp remove_quoted_code(ast) do
    Macro.prewalk(ast, fn
      {:quote, _meta, _args} -> nil
      node -> node
    end)
  end

  defp collect_scope_describe_lines(body, inherited_aliases) do
    body
    |> top_level_expressions()
    |> Enum.reduce({inherited_aliases, MapSet.new()}, &collect_scope_expression/2)
    |> elem(1)
  end

  defp collect_scope_expression(
         {:alias, _meta, _args} = alias_ast,
         {aliases, lines}
       ) do
    {update_aliases(aliases, alias_ast), lines}
  end

  defp collect_scope_expression(
         {:defmodule, _meta, [_module, options]},
         {aliases, lines}
       )
       when is_list(options) do
    nested_lines =
      options
      |> Keyword.get(:do)
      |> collect_scope_describe_lines(aliases)

    {aliases, MapSet.union(lines, nested_lines)}
  end

  defp collect_scope_expression(
         {:__block__, _meta, expressions},
         {aliases, lines}
       ) do
    Enum.reduce(expressions, {aliases, lines}, &collect_scope_expression/2)
  end

  defp collect_scope_expression(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, module_parts}, :describe]}, meta,
          arguments},
         {aliases, lines}
       ) do
    lines =
      if resolves_to_ex_unit_case?(module_parts, aliases) do
        MapSet.put(lines, meta[:line])
      else
        lines
      end

    collect_nested_scope_lines(arguments, aliases, lines)
  end

  defp collect_scope_expression({_name, _meta, arguments}, {aliases, lines})
       when is_list(arguments) do
    collect_nested_scope_lines(arguments, aliases, lines)
  end

  defp collect_scope_expression(expression, {aliases, lines}) when is_list(expression) do
    collect_nested_scope_lines(expression, aliases, lines)
  end

  defp collect_scope_expression({_key, value}, {aliases, lines}) do
    {_nested_aliases, nested_lines} = collect_scope_expression(value, {aliases, MapSet.new()})
    {aliases, MapSet.union(lines, nested_lines)}
  end

  defp collect_scope_expression(_expression, scope), do: scope

  defp resolves_to_ex_unit_case?([module], aliases) do
    aliases
    |> Map.get(module)
    |> ex_unit_case_parts?()
  end

  defp resolves_to_ex_unit_case?([:ExUnit, :Case], aliases) do
    not Map.has_key?(aliases, :ExUnit)
  end

  defp resolves_to_ex_unit_case?(_module_parts, _aliases), do: false

  defp ex_unit_case_parts?([:ExUnit, :Case]), do: true
  defp ex_unit_case_parts?([:"Elixir", :ExUnit, :Case]), do: true
  defp ex_unit_case_parts?(_parts), do: false

  defp collect_nested_scope_lines(expressions, aliases, lines) do
    Enum.reduce(expressions, {aliases, lines}, fn expression, {aliases, lines} ->
      {_nested_aliases, nested_lines} =
        collect_scope_expression(expression, {aliases, MapSet.new()})

      {aliases, MapSet.union(lines, nested_lines)}
    end)
  end

  defp top_level_expressions({:__block__, _meta, expressions}), do: expressions
  defp top_level_expressions(expression), do: [expression]

  defp collect_local_describe_lines(body) do
    defines_describe_two? =
      body
      |> top_level_expressions()
      |> Enum.any?(&defines_describe_two?/1)

    local_lines =
      if defines_describe_two? do
        body
        |> remove_nested_modules()
        |> collect_unqualified_describe_lines()
      else
        MapSet.new()
      end

    {_body, nested_lines} =
      Macro.prewalk(body, MapSet.new(), fn
        {:defmodule, _meta, [_module, options]}, lines when is_list(options) ->
          nested_lines =
            options
            |> Keyword.get(:do)
            |> collect_local_describe_lines()

          {nil, MapSet.union(lines, nested_lines)}

        ast, lines ->
          {ast, lines}
      end)

    MapSet.union(local_lines, nested_lines)
  end

  defp collect_imported_describe_lines(body, inherited_non_ex_unit_import?) do
    body
    |> top_level_expressions()
    |> Enum.reduce(
      {inherited_non_ex_unit_import?, MapSet.new()},
      &collect_import_scope_expression/2
    )
    |> elem(1)
  end

  defp collect_import_scope_expression(
         {:import, _meta, _args} = import_ast,
         {imported?, lines}
       ) do
    case describe_import_origin(import_ast) do
      :non_ex_unit -> {true, lines}
      :ex_unit -> {false, lines}
      :unrelated -> {imported?, lines}
    end
  end

  defp collect_import_scope_expression(
         {:defmodule, _meta, [_module, options]},
         {imported?, lines}
       )
       when is_list(options) do
    nested_lines =
      options
      |> Keyword.get(:do)
      |> collect_imported_describe_lines(imported?)

    {imported?, MapSet.union(lines, nested_lines)}
  end

  defp collect_import_scope_expression(
         {:__block__, _meta, expressions},
         {imported?, lines}
       ) do
    Enum.reduce(expressions, {imported?, lines}, &collect_import_scope_expression/2)
  end

  defp collect_import_scope_expression(
         {:describe, meta, [_name, [do: _body]]},
         {true, lines}
       ) do
    {true, MapSet.put(lines, meta[:line])}
  end

  defp collect_import_scope_expression({_name, _meta, arguments}, {imported?, lines})
       when is_list(arguments) do
    collect_nested_import_lines(arguments, imported?, lines)
  end

  defp collect_import_scope_expression(expression, {imported?, lines})
       when is_list(expression) do
    collect_nested_import_lines(expression, imported?, lines)
  end

  defp collect_import_scope_expression({_key, value}, {imported?, lines}) do
    {_nested_imported?, nested_lines} =
      collect_import_scope_expression(value, {imported?, MapSet.new()})

    {imported?, MapSet.union(lines, nested_lines)}
  end

  defp collect_import_scope_expression(_expression, scope), do: scope

  defp collect_nested_import_lines(expressions, imported?, lines) do
    Enum.reduce(expressions, {imported?, lines}, fn expression, {imported?, lines} ->
      {_nested_imported?, nested_lines} =
        collect_import_scope_expression(expression, {imported?, MapSet.new()})

      {imported?, MapSet.union(lines, nested_lines)}
    end)
  end

  defp describe_import_origin(
         {:import, _meta, [{:__aliases__, _alias_meta, module_parts}, options]}
       )
       when is_list(options) do
    if options
       |> Keyword.get(:only, [])
       |> Enum.any?(&match?({:describe, 2}, &1)) do
      if module_parts == [:ExUnit, :Case] do
        :ex_unit
      else
        :non_ex_unit
      end
    else
      :unrelated
    end
  end

  defp describe_import_origin({:import, _meta, [{:__aliases__, _alias_meta, module_parts}]}) do
    if ex_unit_case_parts?(module_parts) do
      :ex_unit
    else
      :non_ex_unit
    end
  end

  defp describe_import_origin(_import_ast), do: :unrelated

  defp defines_describe_two?({definition, _meta, [head | _body]})
       when definition in [:def, :defp, :defmacro, :defmacrop] do
    describe_two_head?(head)
  end

  defp defines_describe_two?(_ast), do: false

  defp describe_two_head?({:describe, _meta, arguments}) when length(arguments) == 2, do: true
  defp describe_two_head?({:when, _meta, [head | _guards]}), do: describe_two_head?(head)
  defp describe_two_head?(_head), do: false

  defp remove_nested_modules(ast) do
    Macro.prewalk(ast, fn
      {:defmodule, _meta, _args} -> nil
      node -> node
    end)
  end

  defp collect_unqualified_describe_lines(ast) do
    {_ast, lines} =
      Macro.prewalk(ast, MapSet.new(), fn
        {:describe, meta, [_name, [do: _body]]} = node, lines ->
          {node, MapSet.put(lines, meta[:line])}

        node, lines ->
          {node, lines}
      end)

    lines
  end

  defp update_aliases(
         aliases,
         {:alias, _meta, [{:__aliases__, _alias_meta, parts}, options]}
       )
       when is_list(options) do
    alias_name =
      case Keyword.get(options, :as) do
        {:__aliases__, _as_meta, [name]} -> name
        _other -> List.last(parts)
      end

    put_or_delete_alias(aliases, alias_name, parts)
  end

  defp update_aliases(aliases, {:alias, _meta, [{:__aliases__, _alias_meta, parts}]}) do
    put_or_delete_alias(aliases, List.last(parts), parts)
  end

  defp update_aliases(
         aliases,
         {:alias, _meta,
          [
            {{:., _dot_meta, [{:__aliases__, _alias_meta, prefix}, :{}]}, _call_meta,
             grouped_aliases}
          ]}
       ) do
    Enum.reduce(grouped_aliases, aliases, fn
      {:__aliases__, _grouped_meta, suffix}, aliases ->
        parts = prefix ++ suffix
        put_or_delete_alias(aliases, List.last(parts), parts)

      _other, aliases ->
        aliases
    end)
  end

  defp update_aliases(aliases, _alias_ast), do: aliases

  defp put_or_delete_alias(aliases, alias_name, parts), do: Map.put(aliases, alias_name, parts)

  defp rename_describe_definition({:describe, meta, args}) do
    {:__bylaw_describe_definition__, meta, args}
  end

  defp rename_describe_definition({:when, meta, [head | guards]}) do
    {:when, meta, [rename_describe_definition(head) | guards]}
  end

  defp rename_describe_definition(head), do: head

  defp rename_quoted_describes(ast) do
    Macro.prewalk(ast, fn
      {:describe, meta, args} ->
        {:__bylaw_quoted_describe__, meta, args}

      {{:., dot_meta, [module, :describe]}, meta, args} ->
        {{:., dot_meta, [module, :__bylaw_quoted_describe__]}, meta, args}

      node ->
        node
    end)
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Avoid `describe` blocks in test files. Give tests descriptive standalone names and split a growing suite into multiple focused test files.",
      trigger: "describe",
      line_no: line_no
    )
  end
end
