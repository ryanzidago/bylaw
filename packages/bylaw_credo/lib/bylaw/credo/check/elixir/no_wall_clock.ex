defmodule Bylaw.Credo.Check.Elixir.NoWallClock do
  @moduledoc """
  Read the wall clock in one clock module only, so a test can control what time it is.

  ## Examples

  Avoid:

        defmodule MyApp.Orders do
          def expired?(order), do: DateTime.compare(order.expires_at, DateTime.utc_now()) == :lt
        end

  Prefer:

        defmodule MyApp.Clock do
          def now, do: DateTime.utc_now()
        end

        defmodule MyApp.Orders do
          def expired?(order), do: DateTime.compare(order.expires_at, MyApp.Clock.now()) == :lt
        end


  Principle: "control time and chance".

  Code that reads the wall clock on its own gives a different answer on every
  run. A test of it passes at 14:00 and fails across midnight, a month end, a
  daylight saving change or on a loaded machine where two reads straddle a
  second. When one module owns the read, a test can freeze or move that
  module's time and every caller follows.

  Outside the modules in `:allowed_modules` and the files in `:allowed_paths`,
  the check reports a call to a function that returns the current calendar
  or system time, with aliases resolved:

  - `DateTime.utc_now`, `DateTime.now` and `DateTime.now!`;
  - `NaiveDateTime.utc_now` and `NaiveDateTime.local_now`;
  - `Date.utc_today`;
  - `Time.utc_now`;
  - `System.os_time` and `System.system_time`;
  - `:os.system_time` and `:os.timestamp`;
  - `:erlang.system_time`, `:erlang.timestamp`, `:erlang.now`,
    `:erlang.localtime`, `:erlang.universaltime`, `:erlang.date` and
    `:erlang.time`;
  - `:calendar.local_time` and `:calendar.universal_time`.

  It also reports the same call written as a capture (`&DateTime.utc_now/0`)
  and as a function tuple such as `autogenerate: {DateTime, :utc_now, []}`.
  Naming the module in a function head default (`now \\\\ DateTime.utc_now()`) is
  a call and is reported: take the time as a plain argument and let the
  caller read the clock module.

  Monotonic time is not reported. `System.monotonic_time`,
  `:erlang.monotonic_time`, `:erlang.unique_integer` and `:timer.tc` measure
  a duration or order events, and their values mean nothing as a date, so they
  cannot make a calendar test depend on today. Pure functions that take a time
  as an argument, such as `DateTime.add/3` or `DateTime.from_unix!/1`, are
  not reported either.

  Not detected: a function imported without its module (`import DateTime`
  followed by `utc_now()`), a call through a variable module, and
  `apply(DateTime, :utc_now, [])`.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoWallClock,
           [
             allowed_modules: [MyApp.Clock],
             allowed_paths: ["priv/repo/migrations/"],
             functions: [{Timex, [:now]}]
           ]}
        ]
      }
    ]
  }
  ```

  - `:allowed_modules` - Modules, and the modules nested in them, whose code
    may read the wall clock. The check matches the name given to
    `defmodule`, including nested `defmodule`s. Defaults to `[]`.
  - `:allowed_paths` - Path substrings or regexes of files where the wall
    clock may be read, such as migrations or seeds. Defaults to `[]`.
  - `:functions` - `{module, functions}` pairs that count as a wall clock
    read. Defaults to the list above; list them again when you add your own.

  ## Usage

  Add this check to Credo's `checks:` list in `.credo.exs`:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Elixir.NoWallClock, [allowed_modules: [MyApp.Clock]]}
        ]
      }
    ]
  }
  ```
  """

  use Credo.Check,
    base_priority: :high,
    category: :warning,
    tags: [:testing],
    param_defaults: [
      allowed_modules: [],
      allowed_paths: [],
      functions: [
        {DateTime, [:utc_now, :now, :now!]},
        {NaiveDateTime, [:utc_now, :local_now]},
        {Date, [:utc_today]},
        {Time, [:utc_now]},
        {System, [:os_time, :system_time]},
        {:os, [:system_time, :timestamp]},
        {:erlang, [:system_time, :timestamp, :now, :localtime, :universaltime, :date, :time]},
        {:calendar, [:local_time, :universal_time]}
      ]
    ],
    explanations: [
      check: @moduledoc,
      params: [
        allowed_modules: "Modules, and the modules nested in them, that may read the wall clock.",
        allowed_paths: "Path substrings or regexes of files where the wall clock may be read.",
        functions: "`{module, functions}` pairs that count as a wall clock read."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    allowed_paths = Params.get(params, :allowed_paths, __MODULE__)

    if RemoteCalls.matches_path?(source_file.filename, allowed_paths) do
      []
    else
      issue_meta = IssueMeta.for(source_file, params)
      ast = Credo.SourceFile.ast(source_file)

      context = %{
        aliases: RemoteCalls.aliases(ast),
        clock: clock_functions(params),
        allowed_modules: module_names(params)
      }

      ast
      |> reads(context, [])
      |> Enum.sort()
      |> Enum.map(fn {line, trigger} -> issue_for(issue_meta, line, trigger, context) end)
    end
  end

  defp clock_functions(params) do
    for {module, functions} <- Params.get(params, :functions, __MODULE__),
        function <- functions,
        into: MapSet.new(),
        do: {RemoteCalls.module_name(module), function}
  end

  defp module_names(params) do
    params
    |> Params.get(:allowed_modules, __MODULE__)
    |> Enum.map(&RemoteCalls.module_name/1)
  end

  defp reads({:defmodule, _meta, [{:__aliases__, _alias_meta, parts}, body]}, context, prefix)
       when is_list(parts) do
    name = module_name(parts, prefix)

    if allowed?(Enum.join(name, "."), context.allowed_modules) do
      []
    else
      reads(body, context, name)
    end
  end

  defp reads({{:., _dot_meta, [module_ast, function]}, meta, args}, context, prefix)
       when is_atom(function) and is_list(args) do
    module = RemoteCalls.resolve(module_ast, context.aliases)

    own =
      if {module, function} in context.clock do
        [{meta[:line] || 0, "#{module}.#{function}"}]
      else
        []
      end

    own ++ reads(args, context, prefix) ++ reads(module_ast, context, prefix)
  end

  defp reads({:{}, meta, [module_ast, function, []]}, context, _prefix) when is_atom(function) do
    module = RemoteCalls.resolve(module_ast, context.aliases)

    if module != nil and {module, function} in context.clock do
      [{meta[:line] || 0, "{#{module}, #{inspect(function)}, []}"}]
    else
      []
    end
  end

  defp reads({form, _meta, args}, context, prefix) when is_list(args) do
    reads(form, context, prefix) ++ reads(args, context, prefix)
  end

  defp reads({left, right}, context, prefix) do
    reads(left, context, prefix) ++ reads(right, context, prefix)
  end

  defp reads(list, context, prefix) when is_list(list) do
    Enum.flat_map(list, &reads(&1, context, prefix))
  end

  defp reads(_other, _context, _prefix), do: []

  defp module_name([{:__MODULE__, _meta, _context} | rest], prefix),
    do: module_name(rest, prefix)

  defp module_name(parts, prefix) do
    if Enum.all?(parts, &is_atom/1) do
      prefix ++ Enum.map(parts, &to_string/1)
    else
      prefix
    end
  end

  defp allowed?(name, allowed_modules) do
    Enum.any?(allowed_modules, &RemoteCalls.within?(name, &1))
  end

  defp issue_for(issue_meta, line_no, trigger, context) do
    format_issue(
      issue_meta,
      message: message(context.allowed_modules),
      trigger: trigger,
      line_no: line_no
    )
  end

  defp message([]) do
    "Control time and chance: do not read the wall clock here; take the time from " <>
      "the application's clock module or as an argument, so a test can set it."
  end

  defp message(allowed_modules) do
    "Control time and chance: do not read the wall clock here; " <>
      "call #{Enum.join(allowed_modules, " or ")} " <>
      "or take the time as an argument, so a test can set it."
  end
end
