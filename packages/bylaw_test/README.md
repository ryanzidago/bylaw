# Bylaw.Test

`bylaw_test` provides a Mix task for running tests while selected Ecto repos
remain stopped. It has no Ecto dependency, so an application can use the task
without making Ecto part of its test tooling dependency graph.

## Installation

Add it as a test-only, compile-time dependency:

```elixir
def deps do
  [
    {:bylaw_test, "~> 0.1.0", only: :test, runtime: false}
  ]
end
```

Until the package is published, a checkout of this repository can use the
package directory directly:

```elixir
{:bylaw_test, path: "../bylaw/packages/bylaw_test", only: :test, runtime: false}
```

After the package is available on GitHub, it can also be installed from its
subdirectory without adding the rest of the repository:

```elixir
{:bylaw_test,
 git: "https://github.com/ryanzidago/bylaw.git",
 subdir: "packages/bylaw_test",
 branch: "main",
 only: :test,
 runtime: false}
```

## Running tests without repos

Run the task from the consuming Mix application with `MIX_ENV=test`:

```sh
MIX_ENV=test mix bylaw_test.without_ecto_repo
```

With no file arguments, the task discovers `*_without_repo_test.exs` files
under the application's `:test_paths`, or under `test/` when no paths are
configured. It loads a `without_repo_helper.exs` once for each participating
test root, in `:test_paths` order. For nested roots, a file belongs to the most
specific root. Ordinary `test_helper.exs` files are not loaded.

For example, with `:test_paths` set to `["lib", "test"]`, files named
`lib/my_repo_without_repo_test.exs` and
`test/my_other_repo_without_repo_test.exs` are discovered, with one optional
`without_repo_helper.exs` loaded from each participating root.

Passing one or more `.exs` paths replaces discovery. Explicit files can be
outside configured test roots; those files do not cause a root helper to load.
Duplicate paths are run once.

By default, the task uses the consumer application's nonempty `:ecto_repos`
list. Pass one or more `--repo Module.Name` options to select repos explicitly;
this replaces the configured list. For example, pass
`--repo MyApp.Repo --repo MyApp.AnalyticsRepo` to select both repos instead of
the configured list. Each selected name must be a loaded Ecto repo
module, and the task checks that no selected repo is registered before and after
helpers and after tests finish. The task itself does not start the consumer app;
project helpers control application startup, which is allowed when the selected
repos remain stopped.

The check observes registered repo processes at those boundaries. It does not
detect a connection opened directly through a driver, nor a repo process that is
started and stopped between checks.

Use `Bylaw.Test.require_repo!/2` in a case template or setup that requires a
particular repo. It raises an `ExUnit.AssertionError` when that repo is selected
for a without-repo run, identifying the repo and the ExUnit case. It is a no-op
for unselected repos and during ordinary ExUnit runs.

```elixir
defmodule MyApp.DatabaseCase do
  use ExUnit.CaseTemplate

  setup context do
    Bylaw.Test.require_repo!(MyApp.Repo, context)
    :ok
  end
end
```
