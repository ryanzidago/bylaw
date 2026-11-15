defmodule Bylaw.Credo.Check.Phoenix.NoRepoInWeb do
  @moduledoc """
  Disallows database access from web modules: LiveViews, components,
  controllers, plugs and anything else under a `*_web/` directory.

  ## Examples

  The check reports:

  - any call on a module whose last segment is `Repo`, such as `Repo.all/1`
    or `MyApp.Repo.get/2`, also through an alias such as
    `alias MyApp.Repo, as: Store`;
  - `import Ecto.Query`;
  - `alias Ecto.Query`, including `alias Ecto.{Changeset, Query}`;
  - any call on `Ecto.Query`, such as `Ecto.Query.from/2`.

  `Ecto.Changeset` and other modules stay allowed, since forms need
  changesets. Test files (`_test.exs`) are never checked.

  Avoid:

        defmodule MyAppWeb.ThingLive.Index do
          use MyAppWeb, :live_view

          import Ecto.Query

          def mount(_params, _session, socket) do
            things = Repo.all(from(t in Thing, where: t.active))
            {:ok, assign(socket, :things, things)}
          end
        end

  Prefer:

        defmodule MyAppWeb.ThingLive.Index do
          use MyAppWeb, :live_view

          alias MyApp.Things

          def mount(_params, _session, socket) do
            {:ok, assign(socket, :things, Things.list_active_things())}
          end
        end

  Logic written inside a LiveView or component can only be reached through
  the UI. When web modules only call context or core functions, every
  behaviour the UI offers lives in a function that the JSON API, background
  jobs and tests can call too, and authorization, query composition and
  domain policy stay in one place. This check extends
  `Bylaw.Credo.Check.Phoenix.NoRepoInController` from controllers to the
  whole web layer and to query building.

  ## Options

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Phoenix.NoRepoInWeb,
           [
             paths: ["lib/my_app_web/"],
             excluded_paths: ["lib/my_app_web/controllers/health_controller.ex"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:paths` - Path substrings or regexes of the web files to check.
    Defaults to `["_web/"]`.
  - `:excluded_paths` - Path substrings or regexes of files to skip, even
    inside `:paths`. Defaults to `[]`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Phoenix.NoRepoInWeb, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :design,
    tags: [:web, :architecture],
    param_defaults: [
      paths: ["_web/"],
      excluded_paths: []
    ],
    explanations: [
      check: @moduledoc,
      params: [
        paths: "Path substrings or regexes of the web files to check.",
        excluded_paths: "Path substrings or regexes of files to skip."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @query_module "Ecto.Query"

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    filename = source_file.filename

    if RemoteCalls.matches_path?(filename, Params.get(params, :paths, __MODULE__)) and
         not String.ends_with?(filename, "_test.exs") and
         not RemoteCalls.matches_path?(filename, Params.get(params, :excluded_paths, __MODULE__)) do
      issues(source_file, params)
    else
      []
    end
  end

  defp issues(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)
    aliases = RemoteCalls.aliases(ast)

    call_issues =
      ast
      |> RemoteCalls.calls()
      |> Enum.flat_map(&call_issue(&1, issue_meta))

    alias_issues =
      ast
      |> Macro.prewalk([], fn node, acc -> {node, query_aliases(node, aliases) ++ acc} end)
      |> elem(1)
      |> Enum.map(&query_issue(issue_meta, "alias #{@query_module}", &1))

    Enum.sort_by(call_issues ++ alias_issues, & &1.line_no)
  end

  defp call_issue(%{module: module, line: line} = call, issue_meta) do
    cond do
      repo?(module) ->
        [repo_issue(issue_meta, RemoteCalls.trigger(call), line)]

      RemoteCalls.within?(module, @query_module) ->
        [query_issue(issue_meta, RemoteCalls.trigger(call), line)]

      true ->
        []
    end
  end

  defp repo?(module), do: module == "Repo" or String.ends_with?(module, ".Repo")

  defp query_aliases(node, aliases) do
    case aliased_modules(node) do
      {line, modules} ->
        if Enum.any?(modules, &query_module?(&1, aliases)) do
          [line]
        else
          []
        end

      nil ->
        []
    end
  end

  defp aliased_modules(
         {:alias, meta, [{:__aliases__, _alias_meta, _parts} = module_ast | _opts]}
       ),
       do: {meta[:line] || 0, [module_ast]}

  defp aliased_modules(
         {:alias, meta,
          [{{:., _dot_meta, [{:__aliases__, _base_meta, base}, :{}]}, _call_meta, children}]}
       ) do
    modules =
      for {:__aliases__, child_meta, child} <- children,
          do: {:__aliases__, child_meta, base ++ child}

    {meta[:line] || 0, modules}
  end

  defp aliased_modules(_node), do: nil

  defp query_module?(module_ast, aliases) do
    case RemoteCalls.resolve(module_ast, aliases) do
      nil -> false
      module -> RemoteCalls.within?(module, @query_module)
    end
  end

  defp repo_issue(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Do not call `Repo` from web code (LiveViews, components, controllers). " <>
          "Call a context or core function instead, so the UI and the API share it.",
      trigger: trigger,
      line_no: line_no
    )
  end

  defp query_issue(issue_meta, trigger, line_no) do
    format_issue(
      issue_meta,
      message:
        "Do not use `Ecto.Query` in web code (LiveViews, components, controllers). " <>
          "Build queries in a context or core module and call it instead, so the UI and the API share it.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
