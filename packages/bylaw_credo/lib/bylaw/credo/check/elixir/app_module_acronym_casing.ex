defmodule Bylaw.Credo.Check.Elixir.AppModuleAcronymCasing do
  @moduledoc """
  App-owned module names should use uppercase acronym words such as `API`,
  `CSV`, `HTTP`, `JSON`, `LLM`, and `UUID`.

  ## Examples

  Avoid:

        defmodule BylawWeb.Api.V1.ToolController do
          alias Bylaw.Accounts.TenantApiKey
          alias Bylaw.TestSupport.ExAwsHttpClient
          alias Bylaw.DatabaseCheck.UuidKeys
        end

  Prefer:

        defmodule BylawWeb.API.V1.ToolController do
          alias Bylaw.Accounts.TenantAPIKey
          alias Bylaw.TestSupport.ExAwsHTTPClient
          alias Bylaw.DatabaseCheck.UUIDKeys
        end

  Mix task modules are exempt because the project intentionally keeps names
  such as `Mix.Tasks.Qa`.

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
          {Bylaw.Credo.Check.Elixir.AppModuleAcronymCasing,
           [
             acronyms: ~w(API CSV HTTP JSON UUID),
             app_roots: ~w(MyApp MyAppWeb),
             exempt_prefixes: ~w(Mix.Tasks),
             relative_roots: ~w(api admin)
           ]}
        ]
      }
    ]
  }
  ```

  - `:acronyms` - Uppercase acronym words to enforce in app-owned module names.
  - `:app_roots` - Absolute app module roots that should be checked.
  - `:exempt_prefixes` - Module prefixes that should always be ignored.
  - `:relative_roots` - Relative module roots to check inside app-owned modules.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.AppModuleAcronymCasing, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :readability,
    param_defaults: [
      acronyms: ~w(API CSV HTTP JSON LLM UUID),
      app_roots: ~w(Bylaw BylawWeb),
      exempt_prefixes: ~w(Mix.Tasks),
      relative_roots: ~w(api)
    ],
    explanations: [
      check: @moduledoc,
      params: [
        acronyms: "Uppercase acronym words to enforce in app-owned module names.",
        app_roots: "Absolute app module roots that should be checked.",
        exempt_prefixes: "Module prefixes that should always be ignored.",
        relative_roots: "Relative module roots to check inside app-owned modules."
      ]
    ]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)

    state = %{
      issue_meta: issue_meta,
      current_module: nil,
      issues: [],
      acronyms: Params.get(params, :acronyms, __MODULE__),
      app_roots: Params.get(params, :app_roots, __MODULE__),
      exempt_prefixes: Params.get(params, :exempt_prefixes, __MODULE__),
      relative_roots: Params.get(params, :relative_roots, __MODULE__)
    }

    state = walk_ast(Credo.SourceFile.ast(source_file), state)
    Enum.reverse(state.issues)
  end

  defp walk_ast({:ok, ast}, state), do: walk(ast, state)
  defp walk_ast(ast, state) when is_tuple(ast), do: walk(ast, state)
  defp walk_ast(_other, state), do: state

  defp walk({:defmodule, meta, [name_ast, body]}, state) do
    state = maybe_add_issue(name_ast, meta, state)

    previous_module = state.current_module

    current_module =
      case extract_alias_segments(name_ast) do
        {:ok, segments} -> segments
        :error -> previous_module
      end

    state = %{state | current_module: current_module}
    state = walk(body, state)
    %{state | current_module: previous_module}
  end

  defp walk({:__aliases__, meta, _segments} = ast, state) do
    maybe_add_issue(ast, meta, state)
  end

  defp walk(tuple, state) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> walk_list(state)
  end

  defp walk(list, state) when is_list(list), do: walk_list(list, state)
  defp walk(_other, state), do: state

  defp walk_list(items, state) do
    Enum.reduce(items, state, &walk(&1, &2))
  end

  defp maybe_add_issue(alias_ast, meta, state) do
    with {:ok, segments} <- extract_alias_segments(alias_ast),
         true <- app_owned_alias?(segments, state),
         {:ok, corrected_name} <- corrected_alias_name(segments, state.acronyms) do
      issue =
        format_issue(
          state.issue_meta,
          message:
            "Use uppercase acronym words in app-owned modules. Prefer `#{corrected_name}` " <>
              "over `#{module_name(segments)}`.",
          trigger: module_name(segments),
          line_no: meta[:line] || 0
        )

      %{state | issues: [issue | state.issues]}
    else
      false -> state
      :error -> state
    end
  end

  defp extract_alias_segments({:__aliases__, _meta, segments}) when is_list(segments) do
    if Enum.all?(segments, &is_atom/1) do
      {:ok, segments}
    else
      :error
    end
  end

  defp extract_alias_segments(_other), do: :error

  defp app_owned_alias?(segments, state) do
    not exempt_prefix?(segments, state.exempt_prefixes) and
      (absolute_app_alias?(segments, state.app_roots) or relative_app_alias?(segments, state))
  end

  defp exempt_prefix?(segments, prefixes) do
    qualified_name = module_name(segments)

    Enum.any?(prefixes, &String.starts_with?(qualified_name, &1))
  end

  defp absolute_app_alias?([root | _rest], app_roots) do
    Atom.to_string(root) in app_roots
  end

  defp absolute_app_alias?(_segments, _app_roots), do: false

  defp relative_app_alias?([root | _rest], %{current_module: current_module} = state)
       when is_list(current_module) do
    absolute_app_alias?(current_module, state.app_roots) and
      Enum.any?(
        state.relative_roots,
        &(String.downcase(Atom.to_string(root)) == String.downcase(&1))
      )
  end

  defp relative_app_alias?(_segments, _state), do: false

  defp corrected_alias_name(segments, acronyms) do
    acronym_map = Map.new(acronyms, &{String.upcase(&1), String.upcase(&1)})

    corrected_segments =
      Enum.map(segments, fn segment ->
        segment
        |> Atom.to_string()
        |> correct_segment(acronym_map)
      end)

    corrected_name = Enum.join(corrected_segments, ".")

    if corrected_name == module_name(segments) do
      :error
    else
      {:ok, corrected_name}
    end
  end

  defp correct_segment(segment, acronym_map) do
    segment
    |> split_words()
    |> Enum.map_join(fn word ->
      Map.get(acronym_map, String.upcase(word), word)
    end)
  end

  defp split_words(segment) do
    case Regex.scan(~r/[A-Z]+(?=[A-Z][a-z]|\d|$)|[A-Z]?[a-z]+|\d+/, segment) do
      [] -> [segment]
      matches -> List.flatten(matches)
    end
  end

  defp module_name(segments), do: Enum.map_join(segments, ".", &Atom.to_string/1)
end
