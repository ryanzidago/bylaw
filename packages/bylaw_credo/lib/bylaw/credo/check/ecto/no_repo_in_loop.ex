defmodule Bylaw.Credo.Check.Ecto.NoRepoInLoop do
  @moduledoc """
  Do not call the repo once per element of a list: read or write all the rows with one query instead.

  ## Examples

  Avoid:

        def load(ids) do
          Enum.map(ids, fn id -> Repo.get(Item, id) end)
        end

        def save(rows) do
          for row <- rows, do: Repo.insert(row)
        end

  Prefer:

        def load(ids) do
          Repo.all(from i in Item, where: i.id in ^ids)
        end

        def save(rows) do
          Repo.insert_all(Item, rows)
        end


  One query per element is an N+1: a list of 20 items makes 20 round trips
  to the database where one query would do, and the cost grows with the
  data. It hides well in development, where lists are short and the database
  is local.

  The check reports a repo call inside a function given to a loop: a
  function of `Enum` or `Stream`, `Task.async_stream`,
  `Task.Supervisor.async_stream` and `async_stream_nolink`, or a function
  listed in `:loop_modules` or `:loop_functions`. It also reports a repo call
  in a `for` comprehension's body, filters and later generators. The first
  generator of a `for`, as in `for item <- Repo.all(query)`, runs once and is
  allowed.

  It follows the module's own functions: `Enum.map(ids, &load/1)` is
  reported when `load`, or a function it calls in the same file, calls the
  repo. Functions are matched by name, across arities. Calls to other
  modules are not followed.

  Where one query per element is deliberate, such as a one-off import or a
  job that must read each tenant on its own, disable the check for that line
  with `# credo:disable-for-next-line Bylaw.Credo.Check.Ecto.NoRepoInLoop`
  or for the file with `credo:disable-for-this-file`, and say why in the
  module's documentation.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.NoRepoInLoop,
           [
             repo_modules: [MyApp.Repo],
             loop_functions: [
               {MyApp.Pricing, [:collect]},
               {Task, [:async_stream]},
               {Task.Supervisor, [:async_stream, :async_stream_nolink]}
             ],
             included_paths: ["lib/"],
             excluded_paths: ["lib/my_app/import/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:repo_modules` - Repo modules whose calls are reported. When empty, any
    module whose last segment is `Repo` is treated as a repo. Defaults to `[]`.
  - `:loop_modules` - Modules whose every function calls the functions it is
    given once per element. Defaults to `[Enum, Stream]`.
  - `:loop_functions` - `{module, functions}` pairs for modules where only
    some functions loop, such as an application's own iterator. Defaults to
    the `async_stream` functions of `Task` and `Task.Supervisor`; list them
    again when you add your own.
  - `:included_paths` - Path substrings or regexes of the files to check.
    Defaults to `["lib/"]`, so tests and seeds may loop over the repo.
  - `:excluded_paths` - Path substrings or regexes of files to skip, even
    inside `:included_paths`. Defaults to `[]`.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Ecto.NoRepoInLoop, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:database, :performance],
    param_defaults: [
      repo_modules: [],
      loop_modules: [Enum, Stream],
      loop_functions: [
        {Task, [:async_stream]},
        {Task.Supervisor, [:async_stream, :async_stream_nolink]}
      ],
      included_paths: ["lib/"],
      excluded_paths: []
    ],
    explanations: [
      check: @moduledoc,
      params: [
        repo_modules:
          "Repo modules to report. When empty, any module whose last segment is Repo is treated as a repo.",
        loop_modules:
          "Modules whose every function calls the functions it is given once per element.",
        loop_functions:
          "`{module, functions}` pairs of functions that call the function they are given once per element.",
        included_paths: "Path substrings or regexes of the files to check.",
        excluded_paths: "Path substrings or regexes of files to skip."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @doc false
  @impl Credo.Check
  def run(%SourceFile{} = source_file, params \\ []) do
    included_paths = Params.get(params, :included_paths, __MODULE__)
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if RemoteCalls.matches_path?(source_file.filename, included_paths) and
         not RemoteCalls.matches_path?(source_file.filename, excluded_paths) do
      issues(source_file, params)
    else
      []
    end
  end

  defp issues(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    ast = SourceFile.ast(source_file)

    context = %{
      aliases: RemoteCalls.aliases(ast),
      repos: module_names(Params.get(params, :repo_modules, __MODULE__)),
      loop_modules: module_names(Params.get(params, :loop_modules, __MODULE__)),
      loop_functions: loop_functions(Params.get(params, :loop_functions, __MODULE__))
    }

    context = Map.put(context, :touching, touching_functions(ast, context))

    ast
    |> Macro.prewalk([], fn node, acc -> {node, loop_bodies(node, context) ++ acc} end)
    |> elem(1)
    |> Enum.flat_map(fn {loop, body} -> repo_calls(body, context, loop) end)
    |> Enum.uniq_by(&{&1.line, &1.trigger})
    |> Enum.sort_by(& &1.line)
    |> Enum.map(&issue_for(issue_meta, &1))
  end

  defp module_names(modules), do: Enum.map(modules, &RemoteCalls.module_name/1)

  defp loop_functions(pairs) do
    for {module, functions} <- pairs,
        function <- functions,
        into: MapSet.new(),
        do: {RemoteCalls.module_name(module), function}
  end

  defp loop_bodies({{:., _meta, [module_ast, function]}, _call_meta, args}, context)
       when is_atom(function) and is_list(args) do
    module = RemoteCalls.resolve(module_ast, context.aliases)

    if loop?(module, function, context) do
      for arg <- args, callback?(arg), do: {"#{module}.#{function}", arg}
    else
      []
    end
  end

  defp loop_bodies({:for, _meta, args}, _context) when is_list(args) do
    {opts, clauses} = Enum.split_with(args, &Keyword.keyword?/1)
    body = for opt <- opts, {:do, value} <- opt, do: value
    Enum.map(Enum.drop(clauses, 1) ++ body, &{"for", &1})
  end

  defp loop_bodies(_node, _context), do: []

  defp loop?(nil, _function, _context), do: false

  defp loop?(module, function, context) do
    module in context.loop_modules or MapSet.member?(context.loop_functions, {module, function})
  end

  defp callback?({:fn, _meta, _clauses}), do: true
  defp callback?({:&, _meta, _args}), do: true
  defp callback?(_arg), do: false

  defp repo_calls(body, context, loop) do
    body
    |> Macro.prewalk([], fn node, acc -> {node, repo_call(node, context, loop) ++ acc} end)
    |> elem(1)
  end

  defp repo_call({{:., meta, [module_ast, function]}, _call_meta, _args}, context, loop)
       when is_atom(function) do
    module = RemoteCalls.resolve(module_ast, context.aliases)

    if repo?(module, context) do
      [%{line: Keyword.get(meta, :line, 0), trigger: "#{module}.#{function}", loop: loop}]
    else
      []
    end
  end

  defp repo_call(
         {:&, meta, [{:/, _slash_meta, [{name, _name_meta, name_context}, _arity]}]},
         context,
         loop
       )
       when is_atom(name) and is_atom(name_context),
       do: local_call(name, meta, context, loop)

  defp repo_call({name, meta, args}, context, loop) when is_atom(name) and is_list(args),
    do: local_call(name, meta, context, loop)

  defp repo_call(_node, _context, _loop), do: []

  defp repo?(nil, _context), do: false

  defp repo?(module, %{repos: []}), do: module == "Repo" or String.ends_with?(module, ".Repo")

  defp repo?(module, %{repos: repos}), do: module in repos

  defp local_call(name, meta, context, loop) do
    if MapSet.member?(context.touching, name) do
      [%{line: Keyword.get(meta, :line, 0), trigger: Atom.to_string(name), loop: loop}]
    else
      []
    end
  end

  defp touching_functions(ast, context) do
    bodies = function_bodies(ast)

    direct =
      for {name, body} <- bodies,
          Enum.any?(body, &calls_repo?(&1, context)),
          into: MapSet.new(),
          do: name

    spread(direct, bodies)
  end

  defp spread(touching, bodies) do
    more =
      for {name, body} <- bodies,
          not MapSet.member?(touching, name),
          Enum.any?(body, &calls_any?(&1, touching)),
          into: touching,
          do: name

    if MapSet.size(more) == MapSet.size(touching) do
      touching
    else
      spread(more, bodies)
    end
  end

  defp function_bodies(ast) do
    ast
    |> Macro.prewalk(%{}, fn
      {kind, _meta, [head, body]} = node, acc when kind in [:def, :defp] ->
        case function_name(head) do
          nil -> {node, acc}
          name -> {node, Map.update(acc, name, [body], &[body | &1])}
        end

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp function_name({:when, _meta, [head | _guards]}), do: function_name(head)
  defp function_name({name, _meta, _args}) when is_atom(name), do: name
  defp function_name(_head), do: nil

  defp calls_repo?(body, context) do
    body
    |> Macro.prewalk(false, fn
      {{:., _meta, [module_ast, _function]}, _call_meta, _args} = node, found ->
        {node, found or repo?(RemoteCalls.resolve(module_ast, context.aliases), context)}

      node, found ->
        {node, found}
    end)
    |> elem(1)
  end

  defp calls_any?(body, names) do
    body
    |> Macro.prewalk(false, fn
      {name, _meta, args} = node, found when is_atom(name) and is_list(args) ->
        {node, found or MapSet.member?(names, name)}

      node, found ->
        {node, found}
    end)
    |> elem(1)
  end

  defp issue_for(issue_meta, issue) do
    format_issue(issue_meta,
      message:
        "#{issue.trigger} runs once per element (in #{issue.loop}): an N+1. " <>
          "Read all rows with one query (a preload, a join, `where: x.id in ^ids`) " <>
          "or write them with one Repo.insert_all/3.",
      trigger: issue.trigger,
      line_no: issue.line
    )
  end
end
