defmodule Bylaw.Credo.Check.Elixir.NoExtraPublicBehaviourFunctions do
  @moduledoc """
  Reports public functions on selected behaviour implementations when those
  functions are not callbacks of the implemented behaviours.

  ## Examples

  This check is opt-in by behaviour. Configure only the behaviours whose
  implementations should expose a minimal public API:

        {Bylaw.Credo.Check.Elixir.NoExtraPublicBehaviourFunctions,
         [
           behaviours: [
             Bylaw.Db.Check,
             Bylaw.Ecto.Query.Check
           ],
           allowed: []
         ]}

  Callback signatures are read from each behaviour module with
  `behaviour_info(:callbacks)`, so the callback list should not be duplicated in
  Credo configuration. Use `:allowed` for intentional extra public functions.

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
          {Bylaw.Credo.Check.Elixir.NoExtraPublicBehaviourFunctions,
           [
             behaviours: [MyApp.Workers.Job],
             allowed: [child_spec: 1],
             excluded_paths: ["test/support/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:behaviours` - Behaviours whose implementations should expose only callback public functions.
  - `:allowed` - Keyword list of intentional extra public functions, such as `[child_spec: 1]`.
  - `:excluded_paths` - List of path prefixes or regexes to exclude from this check.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoExtraPublicBehaviourFunctions, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :design,
    param_defaults: [behaviours: [], allowed: [], excluded_paths: []],
    explanations: [
      check: @moduledoc,
      params: [
        behaviours:
          "Behaviours whose implementations should expose only callback public functions.",
        allowed: "Keyword list of intentional extra public functions, such as `[child_spec: 1]`.",
        excluded_paths: "List of path prefixes or regexes to exclude from this check."
      ]
    ]

  alias Credo.SourceFile

  @doc false
  @impl Credo.Check
  @spec run(SourceFile.t(), Keyword.t()) :: list(Credo.Issue.t())
  def run(%SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if excluded?(source_file.filename, excluded_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)

      state = %{
        issue_meta: issue_meta,
        behaviours: MapSet.new(Params.get(params, :behaviours, __MODULE__)),
        callbacks_by_behaviour: callbacks_by_behaviour(params),
        allowed: allowed_signatures(params),
        issues: []
      }

      source_file
      |> SourceFile.ast()
      |> find_issues(state)
    end
  end

  defp find_issues({:ok, ast}, state), do: find_issues(ast, state)

  defp find_issues(ast, state) when is_tuple(ast) do
    ast
    |> Macro.prewalk(state, &traverse/2)
    |> elem(1)
    |> Map.fetch!(:issues)
    |> Enum.reverse()
  end

  defp find_issues(_other, _state), do: []

  defp traverse({:defmodule, _meta, [_module_ast, [do: body]]} = ast, state) do
    {ast, report_module(body, state)}
  end

  defp traverse(ast, state), do: {ast, state}

  defp report_module(body, state) do
    aliases = aliases(body)

    implemented_behaviours =
      body
      |> direct_children()
      |> Enum.flat_map(&behaviour_attribute(&1, aliases))
      |> Enum.filter(&MapSet.member?(state.behaviours, &1))

    allowed_callbacks = callback_signatures(implemented_behaviours, state.callbacks_by_behaviour)

    if Enum.empty?(allowed_callbacks) do
      state
    else
      body
      |> direct_children()
      |> Enum.flat_map(&public_definition_signatures/1)
      |> Enum.reject(&MapSet.member?(allowed_callbacks, signature(&1)))
      |> Enum.reject(&MapSet.member?(state.allowed, signature(&1)))
      |> Enum.uniq_by(&signature/1)
      |> Enum.reduce(state, &add_issue/2)
    end
  end

  defp callbacks_by_behaviour(params) do
    params
    |> Params.get(:behaviours, __MODULE__)
    |> Enum.reduce(%{}, fn behaviour, callbacks_by_behaviour ->
      Map.put(callbacks_by_behaviour, behaviour, behaviour_callbacks(behaviour))
    end)
  end

  defp behaviour_callbacks(behaviour) when is_atom(behaviour) do
    if Code.ensure_loaded?(behaviour) and function_exported?(behaviour, :behaviour_info, 1) do
      behaviour
      |> apply(:behaviour_info, [:callbacks])
      |> MapSet.new()
    else
      MapSet.new()
    end
  rescue
    _error -> MapSet.new()
  end

  defp behaviour_callbacks(_behaviour), do: MapSet.new()

  defp callback_signatures(behaviours, callbacks_by_behaviour) do
    behaviours
    |> Enum.map(&Map.get(callbacks_by_behaviour, &1, MapSet.new()))
    |> Enum.reduce(MapSet.new(), &MapSet.union/2)
  end

  defp allowed_signatures(params) do
    params
    |> Params.get(:allowed, __MODULE__)
    |> Enum.flat_map(fn
      {name, arity} when is_atom(name) and is_integer(arity) -> [{name, arity}]
      _other -> []
    end)
    |> MapSet.new()
  end

  defp direct_children({:__block__, _meta, children}), do: children
  defp direct_children(nil), do: []
  defp direct_children(child), do: [child]

  defp aliases(body) do
    body
    |> direct_children()
    |> Enum.flat_map(&alias_entries/1)
    |> Map.new()
  end

  defp alias_entries({:alias, _meta, [{:__aliases__, _aliases_meta, aliases}]}) do
    [{List.last(aliases), Module.concat(aliases)}]
  end

  defp alias_entries(
         {:alias, _meta, [{:__aliases__, _aliases_meta, aliases}, [as: {:__aliases__, _, [as]}]]}
       ) do
    [{as, Module.concat(aliases)}]
  end

  defp alias_entries(_ast), do: []

  defp behaviour_attribute({:@, _meta, [{:behaviour, _attribute_meta, [behaviour_ast]}]}, aliases) do
    case module_attribute_value(behaviour_ast, aliases) do
      {:ok, behaviour} -> [behaviour]
      :error -> []
    end
  end

  defp behaviour_attribute(_ast, _aliases), do: []

  defp module_attribute_value({:__aliases__, _meta, [alias]}, aliases) do
    {:ok, Map.get(aliases, alias, alias)}
  end

  defp module_attribute_value({:__aliases__, _meta, [alias | rest]}, aliases) do
    root = Map.get(aliases, alias, alias)
    {:ok, Module.concat([root | rest])}
  end

  defp module_attribute_value(behaviour, _aliases) when is_atom(behaviour), do: {:ok, behaviour}
  defp module_attribute_value(_ast, _aliases), do: :error

  defp public_definition_signatures({:def, _meta, [head | _body]}) do
    case definition_head(head) do
      {:ok, name, meta, params} ->
        params
        |> public_arities()
        |> Enum.map(&%{name: name, arity: &1, line_no: meta[:line] || 0})

      :error ->
        []
    end
  end

  defp public_definition_signatures({:defdelegate, _meta, [head | _opts]}) do
    case definition_head(head) do
      {:ok, name, meta, params} ->
        params
        |> public_arities()
        |> Enum.map(&%{name: name, arity: &1, line_no: meta[:line] || 0})

      :error ->
        []
    end
  end

  defp public_definition_signatures(_ast), do: []

  defp definition_head({:when, _meta, [call | _guards]}), do: definition_head(call)

  defp definition_head({name, meta, params}) when is_atom(name) and is_list(params) do
    {:ok, name, meta, params}
  end

  defp definition_head(_head), do: :error

  defp public_arities(params) do
    arity = Enum.count(params)
    default_count = Enum.count(params, &default_argument?/1)

    (arity - default_count)..arity
    |> Enum.to_list()
    |> Enum.uniq()
  end

  defp default_argument?({:\\, _meta, [_param, _default]}), do: true
  defp default_argument?(_param), do: false

  defp add_issue(%{name: name, arity: arity, line_no: line_no}, state) do
    issue =
      format_issue(
        state.issue_meta,
        message:
          "Public function `#{name}/#{arity}` is not a callback of the configured behaviour. " <>
            "Make it private, add a callback to the behaviour, or list it in `:allowed`.",
        trigger: "#{name}/#{arity}",
        line_no: line_no
      )

    %{state | issues: [issue | state.issues]}
  end

  defp signature(%{name: name, arity: arity}), do: {name, arity}

  defp excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, fn
      %Regex{} = regex -> Regex.match?(regex, filename)
      path when is_binary(path) -> String.contains?(filename, path)
    end)
  end
end
