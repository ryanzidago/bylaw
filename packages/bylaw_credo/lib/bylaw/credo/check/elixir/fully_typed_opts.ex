defmodule Bylaw.Credo.Check.Elixir.FullyTypedOpts do
  @moduledoc """
  Fully type option lists instead of using `keyword()` or `Keyword.t()` for
  `opts` parameters or `*_opts` type aliases.

  ## Examples

  Avoid:

        @spec search(query :: String.t(), opts :: keyword()) :: result()
        @type search_opts :: Keyword.t()
  Prefer:

        @type search_opt ::
                {:max_results, pos_integer()}
                | {:country, String.t()}

        @type search_opts :: [search_opt()]

        @spec search(query :: String.t(), opts :: search_opts()) :: result()

  ## Notes

  Path exclusions are matched against the source filename and are intended for generated files or temporary migration areas.

  The check uses static AST analysis, so dynamic code generation and macro-expanded code may fall outside its signal.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.FullyTypedOpts,
           [
             excluded_paths: ["test/support/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:excluded_paths` - List of path prefixes or regexes to exclude from this check.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.FullyTypedOpts, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        excluded_paths: "List of path prefixes or regexes to exclude from this check."
      ]
    ]

  alias Credo.SourceFile

  @typespec_attributes [:spec, :callback, :macrocallback, :type, :typep, :opaque]
  @callable_typespec_attributes [:spec, :callback, :macrocallback]
  @type_typespec_attributes [:type, :typep, :opaque]
  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if excluded?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> SourceFile.ast()
      |> find_issues(issue_meta)
    end
  end

  defp find_issues({:ok, ast}, issue_meta) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
    |> Enum.reverse()
  end

  defp find_issues(ast, issue_meta) when is_tuple(ast) do
    ast
    |> Macro.prewalk([], &traverse(&1, &2, issue_meta))
    |> elem(1)
    |> Enum.reverse()
  end

  defp find_issues(_other, _issue_meta), do: []

  defp traverse({:@, _meta, [{attribute, _attribute_meta, arguments}]} = node, issues, issue_meta)
       when attribute in @typespec_attributes do
    issues = Enum.reduce(arguments, issues, &traverse_attribute(&1, attribute, &2, issue_meta))
    {node, issues}
  end

  defp traverse(node, issues, _issue_meta), do: {node, issues}

  defp traverse_attribute(
         {:when, _meta, [typespec | _constraints]},
         attribute,
         issues,
         issue_meta
       ),
       do: traverse_attribute(typespec, attribute, issues, issue_meta)

  defp traverse_attribute(
         {:"::", _meta, [signature, _return_type]},
         attribute,
         issues,
         issue_meta
       )
       when attribute in @callable_typespec_attributes do
    traverse_signature(signature, issues, issue_meta)
  end

  defp traverse_attribute(
         {:"::", meta, [name_ast, type_ast]} = ast,
         attribute,
         issues,
         issue_meta
       )
       when attribute in @type_typespec_attributes do
    if opts_name?(name_ast) and broad_keyword_type?(type_ast) do
      [issue_for(issue_meta, meta[:line] || 0, Macro.to_string(ast)) | issues]
    else
      issues
    end
  end

  defp traverse_attribute(_ast, _attribute, issues, _issue_meta), do: issues

  defp traverse_signature({_name, _meta, arguments}, issues, issue_meta)
       when is_list(arguments) do
    Enum.reduce(arguments, issues, &traverse_argument(&1, &2, issue_meta))
  end

  defp traverse_signature(_signature, issues, _issue_meta), do: issues

  defp traverse_argument({:"::", meta, [name_ast, type_ast]} = ast, issues, issue_meta) do
    if opts_name?(name_ast) and broad_keyword_type?(type_ast) do
      [issue_for(issue_meta, meta[:line] || 0, Macro.to_string(ast)) | issues]
    else
      issues
    end
  end

  defp traverse_argument(_arg, issues, _issue_meta), do: issues

  defp opts_name?({name, _meta, _context}) when is_atom(name) do
    name_string = Atom.to_string(name)
    name == :opts or String.ends_with?(name_string, "_opts")
  end

  defp opts_name?(_ast), do: false

  defp broad_keyword_type?({:keyword, _meta, []}), do: true

  defp broad_keyword_type?(
         {{:., _dot_meta, [{:__aliases__, _alias_meta, [:Keyword]}, :t]}, _call_meta, []}
       ),
       do: true

  defp broad_keyword_type?(_ast), do: false

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Fully type option lists. Replace `#{trigger}` with a concrete `*_opts()` alias " <>
          "that enumerates supported keys and value types.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, fn
      %Regex{} = regex -> Regex.match?(regex, filename)
      path when is_binary(path) -> String.contains?(filename, path)
    end)
  end
end
