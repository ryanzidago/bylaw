# Bylaw.Test

`bylaw_test` provides ExUnit runtime guards for Bylaw consumers. Today it
provides `Bylaw.Test.SandboxUsage`, which detects passing tests that checked out
an Ecto SQL sandbox without running any real SQL queries, so database-independent
tests stay in `ExUnit.Case`.

It has no Ecto dependency, listening instead to the application's configured
query telemetry events.

## Installation

Add it as a test-only dependency:

```elixir
def deps do
  [
    {:bylaw_test, "~> 0.1.0", only: :test}
  ]
end
```

Until the package is published, it can also be installed from its GitHub
subdirectory:

```elixir
{:bylaw_test,
 git: "https://github.com/ryanzidago/bylaw.git",
 subdir: "packages/bylaw_test",
 branch: "main",
 only: :test}
```

## Detecting unused database sandboxes

1. Start `Bylaw.Test.SandboxUsage` in `test/test_helper.exs`, passing your repo's
   query telemetry event(s) and any per-test plumbing queries to ignore.
2. Add `Bylaw.Test.SandboxUsage.Formatter` to `ExUnit.start/1` and register
   `ExUnit.after_suite(&Bylaw.Test.SandboxUsage.check!/1)`.
3. Call `Bylaw.Test.SandboxUsage.watch/2` from your database case template setup.

```elixir
# test/test_helper.exs
{:ok, _} =
  Bylaw.Test.SandboxUsage.start_link(
    events: [[:my_app, :repo, :query]],
    ignore: [~r/\bset_config\('application_name'/i]
  )

ExUnit.start(formatters: [ExUnit.CLIFormatter, Bylaw.Test.SandboxUsage.Formatter])
ExUnit.after_suite(&Bylaw.Test.SandboxUsage.check!/1)
```

```elixir
# test/support/data_case.ex
setup tags do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(MyApp.Repo, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

  unless tags[:allow_unused_sandbox] do
    Bylaw.Test.SandboxUsage.watch(tags)
  end

  :ok
end
```

Built-in SQL transaction plumbing (`BEGIN`, `COMMIT`, `ROLLBACK`, `SAVEPOINT`,
`RELEASE SAVEPOINT`, `ROLLBACK TO SAVEPOINT`) is ignored automatically.

- Queries executed directly by the test process or by spawned processes with
  `$callers` (such as `Task.async` or LiveView processes) are credited to that
  test.
- When `shared: true` (the default when `tags[:async]` is false/absent), queries
  from background processes without `$callers` are credited to active shared
  tests.
- Failing or skipped tests do not produce unused-sandbox violations.
- Any passing watched test that runs zero non-plumbing SQL queries fails
  `check!/1` with its `file:line`, module, and test name.
