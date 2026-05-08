defmodule Bylaw.Credo.Check.Ecto.OwnContextForSchema do
  @moduledoc """
  Enforces that each Ecto schema lives under its own dedicated context module.

  A schema `Bylaw.Foos.Foo` is correctly placed because `Foos` is the
  context for `Foo`. A schema `Bylaw.Runs.ToolCall` is incorrectly placed
  because `Runs` is the context for `Run`, not `ToolCall` - it should be
  `Bylaw.ToolCalls.ToolCall`.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :design,
    param_defaults: [excluded_modules: []],
    explanations: [
      check: """
      Each Ecto schema should live under its own dedicated context module.

      ## Why?

      Keeping one schema per context ensures that context modules stay small
      and focused. When a schema is nested under another schema's context
      (e.g. `Bylaw.Runs.ToolCall`), the context tends to accumulate
      unrelated responsibilities.

      ## Examples

      Bad - `ToolCall` is nested under the `Runs` context:

          defmodule Bylaw.Runs.ToolCall do
            use Bylaw.Schema
          end

      Good - `ToolCall` has its own context:

          defmodule Bylaw.ToolCalls.ToolCall do
            use Bylaw.Schema
          end
      """,
      params: [
        excluded_modules:
          "List of fully qualified module names (as strings) to exclude from this check."
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    excluded_modules = Params.get(params, :excluded_modules, __MODULE__)

    source_file
    |> Credo.SourceFile.ast()
    |> collect_issues(issue_meta, excluded_modules)
  end

  defp collect_issues(ast, issue_meta, excluded_modules) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta, excluded_modules))
    |> elem(1)
  end

  defp traverse(
         {:defmodule, meta, [{:__aliases__, _meta, module_parts}, [do: body]]} = ast,
         issues,
         issue_meta,
         excluded_modules
       ) do
    module_name = Enum.map_join(module_parts, ".", &Atom.to_string/1)

    if uses_bylaw_schema?(body) and module_name not in excluded_modules do
      case check_context_match(module_parts, module_name) do
        :ok ->
          {ast, issues}

        {:error, parent_name, schema_name} ->
          issue =
            format_issue(
              issue_meta,
              message:
                "`#{schema_name}` should not live under `#{parent_name}`. " <>
                  "Move it to its own context (e.g. `#{suggest_context(schema_name)}.#{schema_name}`).",
              trigger: module_name,
              line_no: meta[:line] || 0
            )

          {ast, [issue | issues]}
      end
    else
      {ast, issues}
    end
  end

  defp traverse(ast, issues, _issue_meta, _excluded_modules), do: {ast, issues}

  defp uses_bylaw_schema?({:__block__, _meta, children}) do
    Enum.any?(children, &uses_bylaw_schema?/1)
  end

  defp uses_bylaw_schema?(
         {:use, _meta, [{:__aliases__, _aliases_meta, [:Bylaw, :Schema]} | _rest]}
       ),
       do: true

  defp uses_bylaw_schema?(_other), do: false

  defp check_context_match(module_parts, _module_name) when length(module_parts) < 3, do: :ok

  defp check_context_match(module_parts, _module_name) do
    schema_name =
      module_parts
      |> List.last()
      |> Atom.to_string()

    parent_name =
      module_parts
      |> Enum.at(-2)
      |> Atom.to_string()

    if context_matches_schema?(parent_name, schema_name) do
      :ok
    else
      {:error, parent_name, schema_name}
    end
  end

  # credo:disable-for-next-line Bylaw.Credo.Check.Elixir.NoPassthroughWrapper
  defp context_matches_schema?(parent, schema) do
    # The parent context should be a pluralized/collection form of the schema name.
    # We check if the parent starts with the schema name (e.g. "Agents" starts with "Agent",
    # "ToolCalls" starts with "ToolCall", "Accounts" starts with "Account").
    String.starts_with?(parent, schema)
  end

  defp suggest_context(schema_name) do
    schema_name <> "s"
  end
end
