defmodule Bylaw.Credo.Check.Testing.NoGlobalStateInAsyncTests do
  @moduledoc """
  Do not change process-wide state from a test module that runs in parallel with others.

  ## Examples

  Avoid:

        defmodule MyApp.MailerTest do
          use ExUnit.Case, async: true

          test "uses the sandbox adapter" do
            Application.put_env(:my_app, :mail_adapter, MyApp.FakeAdapter)
            assert {:ok, _email} = MyApp.Mailer.deliver(email())
          end
        end

  Prefer:

        defmodule MyApp.MailerTest do
          use ExUnit.Case, async: true

          test "uses the given adapter" do
            assert {:ok, _email} = MyApp.Mailer.deliver(email(), adapter: MyApp.FakeAdapter)
          end
        end


  Principle: "own your state".

  Test modules marked `async: true` run at the same time as other modules.
  Application and system environment, named processes, named ETS tables and
  `:persistent_term` exist once per node, so two modules that write the same
  entry overwrite each other, and a test passes or fails depending on which
  module got there first. Pass the value in as an argument or an option,
  start a process with no name and keep its pid, or move the module to
  `async: false` so ExUnit runs it alone.

  In a module that has `use SomeCase, async: true`, the check reports:

  - `Application.put_env`, `Application.put_all_env` and
    `Application.delete_env`, `System.put_env` and `System.delete_env`,
    `Logger.configure`, `Mox.set_mox_global` and `Hammox.set_mox_global`
    (and `setup :set_mox_global`), listed in `:functions`;
  - `Process.register(pid, name)` and `:erlang.register(name, pid)` with a
    fixed name: an atom, a module name or `__MODULE__`;
  - `:ets.new(name, options)` with `:named_table` in the options and a fixed
    name;
  - `:persistent_term.put` and `:persistent_term.erase` with a fixed key: no
    variable or function call in it;
  - a `name:` option with a fixed name (an atom, a module name, `__MODULE__`
    or `{:global, fixed_name}`) in a call to `start_link`, `start`,
    `start_supervised` or `start_supervised!`, also inside a child
    specification such as `{MyApp.Counter, name: MyApp.Counter}`.

  The syntax tree cannot tell these reliably, so the check leaves them out:

  - a global write made by another module, such as a fixture in
    `test/support/` that calls `Application.put_env`, or a function the test
    calls that registers a process;
  - a name or key held in a variable or built at run time, which may or may
    not be unique per test;
  - writes to a table or a key that already exists, such as `:ets.insert/2`
    on a named table, the file system, the database, and the logger level
    set through anything but `Logger.configure`;
  - whether another async module really uses the same name. A fixed name is
    reported because it can clash.

  `Bylaw.Credo.Check.Testing.NoGlobalStateInTests` reports reading and
  writing the environment in every test module, async or not; this check
  targets the writes that race and reports more kinds of global state, but
  only in modules that run in parallel. Enabling both reports an
  `Application.put_env` twice.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoGlobalStateInAsyncTests,
           [
             included_paths: [~r"_test\\.exs$"],
             excluded_paths: ["test/legacy/"],
             functions: [{MyApp.Settings, [:put, :delete]}]
           ]}
        ]
      }
    ]
  }
  ```

  - `:included_paths` - Path substrings or regexes of the files to check.
    Defaults to `[~r"_test\\.exs$"]`.
  - `:excluded_paths` - Path substrings or regexes of files to skip, even
    inside `:included_paths`. Defaults to `[]`.
  - `:functions` - `{module, functions}` pairs of calls that change global
    state. Defaults to the environment, logger and Mox functions listed
    above; list them again when you add your own.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoGlobalStateInAsyncTests, []}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :higher,
    category: :warning,
    tags: [:testing],
    param_defaults: [
      included_paths: [~r"_test\.exs$"],
      excluded_paths: [],
      functions: [
        {Application, [:put_env, :put_all_env, :delete_env]},
        {System, [:put_env, :delete_env]},
        {Logger, [:configure]},
        {Mox, [:set_mox_global]},
        {Hammox, [:set_mox_global]}
      ]
    ],
    explanations: [
      check: @moduledoc,
      params: [
        included_paths: "Path substrings or regexes of the files to check.",
        excluded_paths: "Path substrings or regexes of files to skip.",
        functions: "`{module, functions}` pairs of calls that change global state."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @starters [:start_link, :start, :start_supervised, :start_supervised!]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
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
    ast = Credo.SourceFile.ast(source_file)

    context = %{
      aliases: RemoteCalls.aliases(ast),
      functions: global_functions(params)
    }

    ast
    |> async_modules()
    |> Enum.flat_map(&global_writes(&1, context))
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(fn {line, trigger} -> issue_for(issue_meta, line, trigger) end)
  end

  defp global_functions(params) do
    for {module, functions} <- Params.get(params, :functions, __MODULE__),
        function <- functions,
        into: MapSet.new(),
        do: {RemoteCalls.module_name(module), function}
  end

  defp async_modules(ast) do
    ast
    |> Macro.prewalk([], fn
      {:defmodule, _meta, [_name, body]} = node, acc ->
        {node, keep_async(body, acc)}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp keep_async(body, acc) do
    if async?(body) do
      [body | acc]
    else
      acc
    end
  end

  defp async?(body) do
    body
    |> Macro.prewalk(false, fn
      {:use, _meta, [_module, options]} = node, acc when is_list(options) ->
        {node, acc or Keyword.get(options, :async) == true}

      node, acc ->
        {node, acc}
    end)
    |> elem(1)
  end

  defp global_writes(body, context) do
    body
    |> Macro.prewalk([], fn node, acc -> {node, global_write(node, context) ++ acc} end)
    |> elem(1)
  end

  defp global_write({{:., _dot_meta, [module_ast, function]}, meta, args}, context)
       when is_atom(function) and is_list(args) do
    module = RemoteCalls.resolve(module_ast, context.aliases)
    line = meta[:line] || 0

    cond do
      {module, function} in context.functions ->
        [{line, "#{module}.#{function}"}]

      global_call?(module, function, args) ->
        [{line, "#{module}.#{function}"}]

      function in @starters ->
        for name <- fixed_names(args),
            do: {name_line(name, line), "name: #{Macro.to_string(name)}"}

      true ->
        []
    end
  end

  defp global_write({:setup, meta, [:set_mox_global]}, _context),
    do: [{meta[:line] || 0, "setup :set_mox_global"}]

  defp global_write({:set_mox_global, meta, args}, _context) when is_list(args),
    do: [{meta[:line] || 0, "set_mox_global"}]

  defp global_write({starter, meta, args}, _context)
       when starter in @starters and is_list(args) do
    for name <- fixed_names(args),
        do: {name_line(name, meta[:line] || 0), "name: #{Macro.to_string(name)}"}
  end

  defp global_write(_node, _context), do: []

  defp global_call?(":persistent_term", function, [key | _rest]) when function in [:put, :erase],
    do: fixed?(key)

  defp global_call?("Process", :register, [_pid, name]), do: fixed?(name)
  defp global_call?(":erlang", :register, [name, _pid]), do: fixed?(name)

  defp global_call?(":ets", :new, [name, options]) when is_list(options),
    do: fixed?(name) and :named_table in options

  defp global_call?(_module, _function, _args), do: false

  defp fixed_names(args) do
    args
    |> Macro.prewalk([], fn
      {:name, name} = node, acc -> {node, keep_fixed_name(name, acc)}
      node, acc -> {node, acc}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp keep_fixed_name(name, acc) do
    if fixed_name?(name) do
      [name | acc]
    else
      acc
    end
  end

  defp name_line(name, default) do
    case name do
      {_form, meta, _args} when is_list(meta) -> Keyword.get(meta, :line, default)
      _other -> default
    end
  end

  defp fixed_name?(name) when is_atom(name), do: name not in [nil, true, false]
  defp fixed_name?({:__aliases__, _meta, _parts}), do: true
  defp fixed_name?({:__MODULE__, _meta, _context}), do: true
  defp fixed_name?({:{}, _meta, [:global, name]}), do: fixed_name?(name)
  defp fixed_name?({:global, name}), do: fixed_name?(name)
  defp fixed_name?(_name), do: false

  defp fixed?({:@, _meta, [{_name, _attr_meta, _context}]}), do: true
  defp fixed?({:__MODULE__, _meta, _context}), do: true
  defp fixed?({:__aliases__, _meta, _parts}), do: true
  defp fixed?({left, right}), do: fixed?(left) and fixed?(right)
  defp fixed?({:{}, _meta, elements}), do: Enum.all?(elements, &fixed?/1)
  defp fixed?(list) when is_list(list), do: Enum.all?(list, &fixed?/1)
  defp fixed?(atom) when is_atom(atom), do: true
  defp fixed?(literal) when is_binary(literal) or is_number(literal), do: true
  defp fixed?(_other), do: false

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Own your state: avoid `#{trigger}` in an async test - it changes state shared with every other test module running at the same time. " <>
          "Pass the value in as an argument or an option, use an unnamed process, or set `async: false`.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
