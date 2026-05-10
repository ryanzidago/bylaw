defmodule Bylaw.Credo.Check.Ecto.OwnContextForSchema do
  @moduledoc """
  Each Ecto schema using a configured schema wrapper should live under its own dedicated context module.

  ## Examples

  Configure the schema wrapper modules that identify application schemas:

  ```elixir
  {Bylaw.Credo.Check.Ecto.OwnContextForSchema,
   [
     schema_modules: [MyApp.Schema]
   ]}
  ```

  Notes:
  Keeping one schema per context ensures that context modules stay small
  and focused. When a schema is nested under another schema's context
  (e.g. `MyApp.Runs.ToolCall`), the context tends to accumulate
  unrelated responsibilities.

  Avoid:
  `ToolCall` is nested under the `Runs` context:

        defmodule MyApp.Runs.ToolCall do
          use MyApp.Schema
        end

  Prefer:
  `ToolCall` has its own context:

        defmodule MyApp.ToolCalls.ToolCall do
          use MyApp.Schema
        end

  ## Notes

  This check uses static AST analysis, so it favors clear source-level patterns over runtime behavior.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.OwnContextForSchema,
           [
             schema_modules: [MyApp.Schema],
             excluded_modules: ["MyApp.Legacy.LegacySchema"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:schema_modules` - Schema wrapper modules that identify application schemas to check.
  - `:excluded_modules` - List of fully qualified module names (as strings) to exclude from this check.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.OwnContextForSchema,
           [
             schema_modules: [MyApp.Schema]
           ]}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :design,
    param_defaults: [schema_modules: [], excluded_modules: []],
    explanations: [
      check: @moduledoc,
      params: [
        schema_modules: "Schema wrapper modules that identify application schemas to check.",
        excluded_modules:
          "List of fully qualified module names (as strings) to exclude from this check."
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    schema_modules = Params.get(params, :schema_modules, __MODULE__)
    excluded_modules = Params.get(params, :excluded_modules, __MODULE__)

    source_file
    |> Credo.SourceFile.ast()
    |> collect_issues(issue_meta, schema_modules, excluded_modules)
  end

  defp collect_issues(ast, issue_meta, schema_modules, excluded_modules) do
    schema_module_names = normalized_schema_module_names(schema_modules)

    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta, schema_module_names, excluded_modules))
    |> elem(1)
  end

  defp traverse(
         {:defmodule, meta, [{:__aliases__, _meta, module_parts}, [do: body]]} = ast,
         issues,
         issue_meta,
         schema_module_names,
         excluded_modules
       ) do
    module_name = Enum.map_join(module_parts, ".", &Atom.to_string/1)

    if uses_schema_module?(body, schema_module_names) and module_name not in excluded_modules do
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

  defp traverse(ast, issues, _issue_meta, _schema_module_names, _excluded_modules),
    do: {ast, issues}

  defp normalized_schema_module_names(schema_modules) do
    Enum.map(schema_modules, fn
      module when is_atom(module) -> Module.split(module) |> Enum.join(".")
      module when is_binary(module) -> module
    end)
  end

  defp uses_schema_module?({:__block__, _meta, children}, schema_module_names) do
    Enum.any?(children, &uses_schema_module?(&1, schema_module_names))
  end

  defp uses_schema_module?(
         {:use, _meta, [{:__aliases__, _aliases_meta, module_parts} | _rest]},
         schema_module_names
       ) do
    module_name = Enum.map_join(module_parts, ".", &Atom.to_string/1)

    module_name in schema_module_names
  end

  defp uses_schema_module?(_other, _schema_module_names), do: false

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
