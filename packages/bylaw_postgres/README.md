# Bylaw.Postgres

## Introduction

Bylaw.Postgres validates the shape of a migrated Postgres database.

It turns database conventions into executable checks: missing foreign-key
indexes, duplicate indexes, nullable foreign keys, required tenant columns,
primary-key type rules, Ecto changeset constraint coverage, and other
schema-level guardrails can fail in CI before they become production drift.

`bylaw_postgres` is the Postgres adapter for `bylaw_db`. Use this package in a
Postgres application; `bylaw_db` provides the shared adapter/check contracts
underneath.

### Without Bylaw.Postgres

Database guardrails usually live in code review, project conventions, scattered
SQL snippets, or custom ExUnit tests. Each rule has to decide how to inspect
Postgres, how to report failures, and how to stay synchronized with the real
migrated schema.

### With Bylaw.Postgres

You configure checks once, run them against the actual migrated test database,
and get structured `Bylaw.Db.Issue` results when the database violates those
rules. The same checks can run against one repo, multiple repos, dynamic repos,
or custom Postgres query targets.

## Installation

Add `bylaw_postgres` to Postgres applications:

```elixir
def deps do
  [
    {:bylaw_postgres, "~> 0.1.0", only: [:dev, :test]}
  ]
end
```

Your application should already have an Ecto SQL repo and Postgres driver
configured.

## Usage

The common application workflow is:

1. Configure the repo and checks in `config/test.exs`.
2. Add one ExUnit test that calls `Bylaw.Db.Adapters.Postgres.validate/0`.
3. Run that test in CI after the test database has been created and migrated.

For example, configure checks in `config/test.exs`:

```elixir
config :bylaw_postgres, Bylaw.Db.Adapters.Postgres,
  repo: MyApp.Repo,
  checks: [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints,
    Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability,
    Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
  ]
```

Then run the configured validation from a test:

```elixir
defmodule MyApp.DatabaseSchemaTest do
  use MyApp.DataCase, async: true

  alias Bylaw.Db.Adapters.Postgres

  describe "database schema guardrails" do
    test "database structure satisfies Bylaw checks" do
      assert :ok = Postgres.validate()
    end
  end
end
```

`Postgres.validate/0` reads the configured repo and checks, builds a Postgres
target, and delegates to `Bylaw.Db.validate/2`.

### Why run this against the test database?

Bylaw should validate the database shape produced by the code under test. In
most Ecto applications, that is the test database:

- it is created and migrated from the current branch before the test suite runs
- it avoids stale tables, indexes, or constraints left behind in a long-lived dev
  database
- it makes failures reproducible in CI because the database shape comes from the
  checked-out migrations
- it fails in the same feedback loop developers already use for migration
  regressions

Running checks against a dev database can still be useful for local exploration,
but it is easier to get noisy failures from unrelated branch work or manual
experiments. Treat the test database as the source of truth for CI guardrails.

### Clearer failure output

`Postgres.validate/0` returns `:ok` or `{:error, issues}`. If you want formatted
failure output in ExUnit, keep that formatting in the test:

```elixir
defmodule MyApp.DatabaseSchemaTest do
  use MyApp.DataCase, async: true

  alias Bylaw.Db.Adapters.Postgres
  alias Bylaw.Db.Issue

  test "database structure satisfies Bylaw checks" do
    case Postgres.validate() do
      :ok -> :ok
      {:error, issues} -> flunk(Issue.format_many(issues))
    end
  end
end
```

### Multiple Postgres targets

A target is one Postgres database or query source that checks can inspect.
Targets are passed as a list because the same checks often need to protect more
than one database boundary.

```elixir
alias Bylaw.Db.Adapters.Postgres

targets = [
  Postgres.target(repo: MyApp.Repo, meta: %{name: :primary}),
  Postgres.target(repo: MyApp.AnalyticsRepo, meta: %{name: :analytics})
]

checks = [
  Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
  Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
]

assert :ok = Postgres.validate(targets, checks)
```

Targets can also be configured:

```elixir
config :bylaw_postgres, Bylaw.Db.Adapters.Postgres,
  targets: [
    [repo: MyApp.Repo, meta: %{name: :primary}],
    [repo: MyApp.AnalyticsRepo, meta: %{name: :analytics}]
  ],
  checks: [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes
  ]
```

## Choosing checks

This README intentionally does not duplicate the check catalog. See the
[`Checks Overview`](guides/checks.md) guide for the built-in check index, rule
option examples, and Ecto changeset constraint setup.

At a high level, each check entry is either a module:

```elixir
Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes
```

or a `{module, opts}` tuple when the check needs project-specific rules:

```elixir
{Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
 rules: [
   [
     only: [schema: "public"],
     columns: ["tenant_id", "inserted_at"],
     except: [[table: "schema_migrations"]]
   ]
 ]}
```

Use options to document intentional exceptions close to the rule. That keeps the
test useful as the database changes: new drift fails, known deviations stay
explicit.
