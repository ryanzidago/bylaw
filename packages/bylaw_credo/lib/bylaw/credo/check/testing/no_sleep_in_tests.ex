defmodule Bylaw.Credo.Check.Testing.NoSleepInTests do
  @moduledoc """
  Avoid sleeping in tests.

  ## Examples

  Avoid:

        test "sends a reminder" do
          Reminders.schedule(user, in: 10)
          Process.sleep(50)
          assert Reminders.sent?(user)
        end

  Prefer:

        test "sends a reminder" do
          Reminders.schedule(user, in: 10, notify: self())
          assert_receive {:reminder_sent, ^user}
        end


  Principle: "wait on a fact, never on time".

  A sleep guesses how long something takes. Guess too short and the test
  fails at random; guess too long and every run pays for it. Wait on a message
  with `assert_receive`, or pass the time in explicitly (for example as an
  argument or a fixture timestamp) instead of waiting for the clock.

  The check reports, in `:included_paths` (by default `*_test.exs` files and
  `test/support/`):

  - `Process.sleep/1` and `:timer.sleep/1`, with aliases resolved;
  - a `receive` that has only an `after` clause and no message clauses, which
    is a sleep written differently: `receive do after 50 -> :ok end`.

  It does not report a sleep forever: `Process.sleep(:infinity)` and
  `receive do after :infinity -> :ok end` keep a spawned process alive and
  wait for nothing. A `receive` with message clauses and an `after` is a wait
  with a limit, not a sleep, and is allowed. A sleep that is the point of a
  test double, such as a fake server that must answer slowly, is disabled
  with `# credo:disable-for-next-line Bylaw.Credo.Check.Testing.NoSleepInTests`
  or by listing the file in `:excluded_paths`.

  ## Options

  Configure options in `.credo.exs` with the check tuple:

  ```elixir
  %{
    configs: [
      %{
        name: "default",
        checks: [
          {Bylaw.Credo.Check.Testing.NoSleepInTests,
           [
             included_paths: [~r"_test\\.exs$", "test/support/"],
             excluded_paths: ["test/support/slow_server.ex"]
           ]}
        ]
      }
    ]
  }
  ```

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
          {Bylaw.Credo.Check.Testing.NoSleepInTests, []}
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
      included_paths: [~r"_test\.exs$", "test/support/"],
      excluded_paths: []
    ],
    explanations: [
      check: @moduledoc,
      params: [
        included_paths: "Path substrings or regexes of the files to check.",
        excluded_paths: "Path substrings or regexes of files to skip."
      ]
    ]

  alias Bylaw.Credo.RemoteCalls

  @sleeps [{"Process", :sleep}, {":timer", :sleep}]

  @doc false
  @impl Credo.Check
  def run(%Credo.SourceFile{} = source_file, params \\ []) do
    included_paths = Params.get(params, :included_paths, __MODULE__)
    excluded_paths = Params.get(params, :excluded_paths, __MODULE__)

    if RemoteCalls.matches_path?(source_file.filename, included_paths) and
         not RemoteCalls.matches_path?(source_file.filename, excluded_paths) do
      issue_meta = IssueMeta.for(source_file, params)
      ast = Credo.SourceFile.ast(source_file)
      aliases = RemoteCalls.aliases(ast)

      ast
      |> Macro.prewalk([], fn node, acc -> {node, sleeps(node, aliases) ++ acc} end)
      |> elem(1)
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map(fn {line, trigger} -> issue_for(issue_meta, line, trigger) end)
    else
      []
    end
  end

  defp sleeps({{:., _dot_meta, [module_ast, function]}, meta, args}, aliases)
       when is_atom(function) and is_list(args) do
    module = RemoteCalls.resolve(module_ast, aliases)

    if {module, function} in @sleeps and not infinity?(args) do
      [{meta[:line] || 0, trigger(module, function)}]
    else
      []
    end
  end

  defp sleeps({:receive, meta, [clauses]}, _aliases) when is_list(clauses) do
    if sleep_receive?(clauses) do
      [{meta[:line] || 0, "receive after"}]
    else
      []
    end
  end

  defp sleeps(_node, _aliases), do: []

  defp sleep_receive?(clauses) do
    case Keyword.get(clauses, :after) do
      [{:->, _arrow_meta, [[timeout], _body]}] ->
        empty_block?(Keyword.get(clauses, :do)) and timeout != :infinity

      _other ->
        false
    end
  end

  defp empty_block?(nil), do: true
  defp empty_block?([]), do: true
  defp empty_block?({:__block__, _meta, []}), do: true
  defp empty_block?(_clauses), do: false

  defp infinity?([:infinity]), do: true
  defp infinity?(_args), do: false

  defp trigger(module, function), do: "#{module}.#{function}"

  defp issue_for(issue_meta, line_no, trigger) do
    format_issue(
      issue_meta,
      message:
        "Avoid `#{trigger}` in tests - it makes tests slow and flaky. " <>
          "Wait on a fact, never on time: wait on a message with `assert_receive`, " <>
          "or pass the time in explicitly instead of waiting for the clock.",
      trigger: trigger,
      line_no: line_no
    )
  end
end
