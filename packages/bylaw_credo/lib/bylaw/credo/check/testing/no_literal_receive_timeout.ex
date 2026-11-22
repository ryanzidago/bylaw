defmodule Bylaw.Credo.Check.Testing.NoLiteralReceiveTimeout do
  @moduledoc """
  Take the timeout of `assert_receive` and `refute_receive` from one shared value, so a slow machine can scale it.

  ## Examples

  Avoid:

        test "sends a reminder" do
          Reminders.schedule(user, notify: self())
          assert_receive {:reminder_sent, ^user}, 500
          refute_receive {:reminder_sent, _other}, 50
        end

  Prefer:

        @receive_timeout MyApp.TestTimeout.scale(500)

        test "sends a reminder" do
          Reminders.schedule(user, notify: self())
          assert_receive {:reminder_sent, ^user}, @receive_timeout
          refute_receive {:reminder_sent, _other}, MyApp.TestTimeout.refute()
        end


  Principle: "wait on a fact, never on time" and "same world everywhere" (a loaded machine must be able to scale the timeout).

  A literal timeout is a guess made on one machine. On a loaded machine, such
  as a CI runner or a laptop running several agents, a message that arrives in
  80 ms takes 600 ms, and `assert_receive ..., 500` fails at random. When every
  test takes its timeout from one helper or module attribute, one place reads
  a factor from the environment and multiplies all of them, and a loaded
  machine is fixed by changing one number.

  The check reports a timeout that is written out in the call: an integer,
  `:timer.seconds(1)` or another `:timer` unit function, `to_timeout(second:
  1)` with literal values, or arithmetic on those. It reports the second
  argument of `assert_receive` and `refute_receive`, and the argument at the
  position given for each function in `:functions`.

  It does not report:

  - a timeout that is a variable, a module attribute, or a call to a
    function, because that is where the scaling lives;
  - a call without a timeout, which uses ExUnit's `:assert_receive_timeout`
    and `:refute_receive_timeout` settings that `ExUnit.configure/1` sets
    once for the whole run;
  - a timeout of `0`, which checks the mailbox now and waits for nothing, and
    `:infinity`.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoLiteralReceiveTimeout,
           [
             functions: [
               {:assert_receive, 2},
               {:refute_receive, 2},
               {:assert_push, 3},
               {:assert_eventually, 2}
             ],
             included_paths: [~r"_test\\.exs$", "test/support/"]
           ]}
        ]
      }
    ]
  }
  ```

  - `:functions` - `{name, position}` pairs: a macro or function that waits,
    and the 1-based position of its timeout argument. Calls with fewer
    arguments are skipped. Defaults to `assert_receive` and
    `refute_receive` at position 2; list them again when you add your own.
    A helper with an optional argument before the timeout, such as
    `assert_reply/4`, is listed at its longest form.
  - `:included_paths` - Path substrings or regexes of the files to check.
    Defaults to `[~r"_test\\.exs$", "test/support/"]`.
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
          {Bylaw.Credo.Check.Testing.NoLiteralReceiveTimeout, []}
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
      functions: [{:assert_receive, 2}, {:refute_receive, 2}],
      included_paths: [~r"_test\.exs$", "test/support/"],
      excluded_paths: []
    ],
    explanations: [
      check: @moduledoc,
      params: [
        functions:
          "`{name, position}` pairs of waiting functions and the 1-based position of their timeout argument.",
        included_paths: "Path substrings or regexes of the files to check.",
        excluded_paths: "Path substrings or regexes of files to skip."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @timer_units [:seconds, :minutes, :hours, :hms, :milliseconds]

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
    pairs = Params.get(params, :functions, __MODULE__)
    functions = Map.new(pairs)

    source_file
    |> Credo.SourceFile.ast()
    |> Macro.prewalk([], fn node, acc -> {node, literal_timeout(node, functions) ++ acc} end)
    |> elem(1)
    |> Enum.sort()
    |> Enum.map(fn {line, name} -> issue_for(issue_meta, line, name) end)
  end

  defp literal_timeout({name, meta, args}, functions) when is_atom(name) and is_list(args) do
    with {:ok, position} <- Map.fetch(functions, name),
         timeout when timeout != nil <- Enum.at(args, position - 1),
         true <- literal_duration?(timeout) and timeout != 0 do
      [{meta[:line] || 0, Atom.to_string(name)}]
    else
      _other -> []
    end
  end

  defp literal_timeout(_node, _functions), do: []

  defp literal_duration?(value) when is_integer(value), do: true

  defp literal_duration?({{:., _dot_meta, [:timer, unit]}, _meta, [arg | _rest]})
       when unit in @timer_units,
       do: literal_duration?(arg)

  defp literal_duration?({:to_timeout, _meta, [options]}) when is_list(options),
    do: Enum.all?(options, fn {_unit, value} -> literal_duration?(value) end)

  defp literal_duration?({operator, _meta, [left, right]}) when operator in [:*, :+, :-],
    do: literal_duration?(left) and literal_duration?(right)

  defp literal_duration?(_other), do: false

  defp issue_for(issue_meta, line_no, name) do
    format_issue(
      issue_meta,
      message:
        "Same world everywhere: do not write the timeout of `#{name}` as a literal; " <>
          "take it from one shared helper or module attribute that a loaded machine can scale.",
      trigger: name,
      line_no: line_no
    )
  end
end
