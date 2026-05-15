defmodule Bylaw.Credo.Check.Ecto.ContextOwnsSchemaQueries do
  @moduledoc """
  Only configured Phoenix context boundary modules may write Ecto queries for
  schemas owned by their namespace.

  ## Examples

  Configure the context boundary modules that own schemas below their namespace:

  ```elixir
  {Bylaw.Credo.Check.Ecto.ContextOwnsSchemaQueries,
   [
     contexts: [
       MyApp.Conversations,
       MyApp.Branches,
       MyApp.Runs
     ]
   ]}
  ```

  Avoid outside `MyApp.Conversations`:

        from(c in Conversation, where: c.id == ^id)
        Conversation |> where([c], c.visible)
        Repo.get_by(Conversation, slug: slug)
        Repo.insert(%Conversation{})

  Prefer:

        MyApp.Conversations.fetch_conversation(id)

  Plain schema references are allowed. This check is specifically about
  writing Ecto query or direct Repo CRUD logic for a schema owned by another
  configured context namespace.

  ## Notes

  A schema module is owned by the longest configured context prefix when the
  schema starts with that context plus one or more extra module segments.
  For example, `MyApp.Conversations.Message` is owned by
  `MyApp.Conversations`.

  Nested modules under a context are not treated as owners by default. Only the
  exact configured context module may write queries for schemas under that
  namespace.

  This check uses static AST analysis, so it favors clear source-level patterns
  over runtime behavior.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.ContextOwnsSchemaQueries,
           [
             contexts: [MyApp.Conversations],
             excluded_modules: [MyApp.Legacy.ReportBuilder],
             excluded_paths: ["lib/my_app/generated/"],
             repo_modules: [MyApp.Repo]
           ]}
        ]
      }
    ]
  }
  ```

  - `:contexts` - Context boundary modules that own schemas below their namespace.
  - `:excluded_modules` - Modules allowed to write queries for owned schemas.
  - `:excluded_paths` - Paths containing any configured string are skipped.
  - `:repo_modules` - Repo modules to inspect. When empty, any module whose last segment is `Repo` is treated as a Repo.
  - `:allow_owner_descendants` - When `true`, modules nested under the owner context may also write queries. Defaults to `false`.
  """

  use Credo.Check,
    base_priority: :higher,
    category: :design,
    param_defaults: [
      contexts: [],
      excluded_modules: [],
      excluded_paths: [],
      repo_modules: [],
      allow_owner_descendants: false
    ],
    explanations: [
      check: @moduledoc,
      params: [
        contexts: "Context boundary modules that own schemas below their namespace.",
        excluded_modules: "Modules allowed to write queries for owned schemas.",
        excluded_paths: "Paths containing any configured string are skipped.",
        repo_modules:
          "Repo modules to inspect. When empty, any module whose last segment is Repo is treated as a Repo.",
        allow_owner_descendants:
          "When true, modules nested under the owner context may also write queries."
      ]
    ]

  @ecto_query_functions ~w(from where or_where select select_merge order_by group_by having
                           or_having preload lock distinct limit offset join left_join
                           right_join inner_join cross_join full_join update union union_all
                           except except_all intersect intersect_all windows combinations)a
  @repo_query_functions ~w(get get! get_by get_by! all one one! aggregate exists? stream)a
  @repo_write_functions ~w(insert insert! update update! delete delete!)a

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if path_excluded?(source_file.filename, excluded_paths) do
      []
    else
      config = %{
        contexts: normalized_modules(Params.get(params, :contexts, __MODULE__)),
        excluded_modules: normalized_modules(Params.get(params, :excluded_modules, __MODULE__)),
        repo_modules: normalized_modules(Params.get(params, :repo_modules, __MODULE__)),
        allow_owner_descendants: Params.get(params, :allow_owner_descendants, __MODULE__)
      }

      issue_meta = IssueMeta.for(source_file, params)

      source_file
      |> Credo.SourceFile.ast()
      |> collect_issues(issue_meta, config)
    end
  end

  defp collect_issues({:ok, ast}, issue_meta, config), do: collect_issues(ast, issue_meta, config)

  defp collect_issues(ast, issue_meta, config) when is_tuple(ast) or is_list(ast) do
    ast
    |> collect_module_issues(issue_meta, config)
    |> Enum.reverse()
  end

  defp collect_issues(_other, _issue_meta, _config), do: []

  defp collect_module_issues(
         {:defmodule, _meta, [{:__aliases__, _aliases_meta, parts}, body]},
         issue_meta,
         config
       ) do
    module = module_name(parts)
    module_body = Keyword.get(body, :do)

    issues =
      if module in config.excluded_modules do
        []
      else
        scan_module_body(module_body, module, issue_meta, config)
      end

    issues ++ collect_module_issues(module_body, issue_meta, config)
  end

  defp collect_module_issues(list, issue_meta, config) when is_list(list) do
    Enum.flat_map(list, &collect_module_issues(&1, issue_meta, config))
  end

  defp collect_module_issues(tuple, issue_meta, config) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> collect_module_issues(issue_meta, config)
  end

  defp collect_module_issues(_other, _issue_meta, _config), do: []

  defp scan_module_body(nil, _current_module, _issue_meta, _config), do: []

  defp scan_module_body(body, current_module, issue_meta, config) do
    body = remove_nested_modules(body)
    aliases = collect_aliases(body)

    body
    |> Macro.prewalk(
      [],
      &traverse_query_logic(&1, &2, aliases, current_module, issue_meta, config)
    )
    |> elem(1)
  end

  defp remove_nested_modules(body) do
    Macro.prewalk(body, fn
      {:defmodule, _meta, _args} -> nil
      node -> node
    end)
  end

  defp collect_aliases(body) do
    body
    |> Macro.prewalk(%{}, &traverse_alias(&1, &2))
    |> elem(1)
  end

  defp traverse_alias(
         {:alias, _meta, [{:__aliases__, _aliases_meta, parts}, opts]} = node,
         aliases
       )
       when is_list(opts) do
    as = Keyword.get(opts, :as)

    aliases =
      case as do
        {:__aliases__, _as_meta, [alias_name]} -> Map.put(aliases, alias_name, parts)
        _other -> aliases
      end

    {node, aliases}
  end

  defp traverse_alias({:alias, _meta, [{:__aliases__, _aliases_meta, parts}]} = node, aliases) do
    {node, Map.put(aliases, List.last(parts), parts)}
  end

  defp traverse_alias(
         {:alias, _meta,
          [
            {{:., _dot_meta, [{:__aliases__, _base_meta, base_parts}, :{}]}, _call_meta, children}
          ]} = node,
         aliases
       ) do
    aliases =
      Enum.reduce(children, aliases, fn
        {:__aliases__, _child_meta, child_parts}, acc ->
          Map.put(acc, List.last(child_parts), base_parts ++ child_parts)

        _other, acc ->
          acc
      end)

    {node, aliases}
  end

  defp traverse_alias(node, aliases), do: {node, aliases}

  defp traverse_query_logic(
         {:from, meta, args} = node,
         issues,
         aliases,
         current_module,
         issue_meta,
         config
       ) do
    {node,
     maybe_add_queryable_issue(
       issues,
       issue_meta,
       config,
       aliases,
       current_module,
       meta,
       args,
       "from"
     )}
  end

  defp traverse_query_logic(
         {{:., _dot_meta, [{:__aliases__, _aliases_meta, [:Ecto, :Query]}, :from]}, meta, args} =
           node,
         issues,
         aliases,
         current_module,
         issue_meta,
         config
       ) do
    {node,
     maybe_add_queryable_issue(
       issues,
       issue_meta,
       config,
       aliases,
       current_module,
       meta,
       args,
       "Ecto.Query.from"
     )}
  end

  defp traverse_query_logic(
         {:|>, _pipe_meta, [left, {function, meta, _args}]} = node,
         issues,
         aliases,
         current_module,
         issue_meta,
         config
       )
       when function in @ecto_query_functions do
    {node,
     maybe_add_schema_issue(
       issues,
       issue_meta,
       config,
       aliases,
       current_module,
       meta,
       left,
       Atom.to_string(function)
     )}
  end

  defp traverse_query_logic(
         {function, meta, [first_arg | _rest]} = node,
         issues,
         aliases,
         current_module,
         issue_meta,
         config
       )
       when function in @ecto_query_functions do
    {node,
     maybe_add_schema_issue(
       issues,
       issue_meta,
       config,
       aliases,
       current_module,
       meta,
       queryable_from_arg(first_arg),
       Atom.to_string(function)
     )}
  end

  defp traverse_query_logic(
         {{:., _dot_meta, [repo, function]}, meta, args} = node,
         issues,
         aliases,
         current_module,
         issue_meta,
         config
       )
       when function in @repo_query_functions do
    issues =
      if repo_module?(repo, aliases, config.repo_modules) do
        maybe_add_schema_issue(
          issues,
          issue_meta,
          config,
          aliases,
          current_module,
          meta,
          List.first(args),
          repo_trigger(repo, function)
        )
      else
        issues
      end

    {node, issues}
  end

  defp traverse_query_logic(
         {{:., _dot_meta, [repo, function]}, meta, args} = node,
         issues,
         aliases,
         current_module,
         issue_meta,
         config
       )
       when function in @repo_write_functions do
    issues =
      if repo_module?(repo, aliases, config.repo_modules) do
        maybe_add_schema_expression_issue(
          issues,
          issue_meta,
          config,
          aliases,
          current_module,
          meta,
          List.first(args),
          repo_trigger(repo, function)
        )
      else
        issues
      end

    {node, issues}
  end

  defp traverse_query_logic(node, issues, _aliases, _current_module, _issue_meta, _config),
    do: {node, issues}

  defp maybe_add_queryable_issue(
         issues,
         issue_meta,
         config,
         aliases,
         current_module,
         meta,
         args,
         trigger
       ) do
    schema =
      args
      |> List.first()
      |> queryable_from_arg()

    maybe_add_schema_issue(
      issues,
      issue_meta,
      config,
      aliases,
      current_module,
      meta,
      schema,
      trigger
    )
  end

  defp maybe_add_schema_expression_issue(
         issues,
         issue_meta,
         config,
         aliases,
         current_module,
         meta,
         expression,
         trigger
       ) do
    case schema_from_expression(expression, aliases) do
      nil ->
        issues

      schema ->
        maybe_add_resolved_schema_issue(
          issues,
          issue_meta,
          config,
          current_module,
          meta,
          schema,
          trigger
        )
    end
  end

  defp maybe_add_schema_issue(
         issues,
         issue_meta,
         config,
         aliases,
         current_module,
         meta,
         expression,
         trigger
       ) do
    case resolve_module(expression, aliases) do
      nil ->
        issues

      schema ->
        maybe_add_resolved_schema_issue(
          issues,
          issue_meta,
          config,
          current_module,
          meta,
          schema,
          trigger
        )
    end
  end

  defp maybe_add_resolved_schema_issue(
         issues,
         issue_meta,
         config,
         current_module,
         meta,
         schema,
         trigger
       ) do
    case owner_context(schema, config.contexts) do
      nil ->
        issues

      owner ->
        if owner_allowed?(current_module, owner, config.allow_owner_descendants) do
          issues
        else
          [issue_for(issue_meta, meta, owner, schema, trigger) | issues]
        end
    end
  end

  defp queryable_from_arg({:in, _meta, [_binding, queryable]}), do: queryable
  defp queryable_from_arg(other), do: other

  defp schema_from_expression({:%, _meta, [schema, {:%{}, _map_meta, _fields}]}, aliases),
    do: resolve_module(schema, aliases)

  defp schema_from_expression({{:., _dot_meta, [schema, _function]}, _call_meta, _args}, aliases),
    do: resolve_module(schema, aliases)

  defp schema_from_expression(_other, _aliases), do: nil

  defp resolve_module({:__aliases__, _meta, [first | rest] = parts}, aliases) do
    case Map.fetch(aliases, first) do
      {:ok, aliased_parts} -> module_name(aliased_parts ++ rest)
      :error -> module_name(parts)
    end
  end

  defp resolve_module(_other, _aliases), do: nil

  defp repo_module?(repo, aliases, []) do
    repo
    |> resolve_module(aliases)
    |> repo_name?()
  end

  defp repo_module?(repo, aliases, repo_modules) do
    case resolve_module(repo, aliases) do
      nil -> false
      module -> module in repo_modules
    end
  end

  defp repo_name?(nil), do: false

  defp repo_name?(module) do
    module
    |> String.split(".")
    |> List.last() == "Repo"
  end

  defp repo_trigger({:__aliases__, _meta, parts}, function),
    do: "#{module_name(parts)}.#{function}"

  defp repo_trigger(_repo, function), do: "Repo.#{function}"

  defp owner_context(schema, contexts) do
    contexts
    |> Enum.filter(&owned_by_context?(schema, &1))
    |> Enum.sort_by(&module_segment_count/1, :desc)
    |> List.first()
  end

  defp module_segment_count(module) do
    module
    |> String.split(".")
    |> Enum.count()
  end

  defp owned_by_context?(schema, context) do
    String.starts_with?(schema, context <> ".")
  end

  defp owner_allowed?(current_module, owner, false), do: current_module == owner

  defp owner_allowed?(current_module, owner, true) do
    current_module == owner or String.starts_with?(current_module, owner <> ".")
  end

  defp issue_for(issue_meta, meta, owner, schema, trigger) do
    format_issue(
      issue_meta,
      message:
        "Only #{owner} may write Ecto queries for #{schema}. " <>
          "Call the owning context or add a function there.",
      trigger: trigger,
      line_no: meta[:line] || 0
    )
  end

  defp normalized_modules(modules) do
    Enum.map(modules, fn
      module when is_atom(module) ->
        module
        |> Module.split()
        |> Enum.join(".")

      module when is_binary(module) ->
        module
    end)
  end

  defp module_name(parts), do: Enum.map_join(parts, ".", &Atom.to_string/1)

  defp path_excluded?(filename, excluded_paths) do
    Enum.any?(excluded_paths, &String.contains?(filename, &1))
  end
end
