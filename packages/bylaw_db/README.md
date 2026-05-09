# Bylaw.Db

## Introduction

Bylaw.Db is the database validation contract layer for Bylaw.

It gives database adapters and checks one shared way to describe what should be
validated, run those validations, and report failures as structured issues.
`bylaw_db` is not enough on its own for validating a real database. For Postgres,
use `bylaw_postgres`; other database adapters can be implemented on top of this
package in the future.

### Without Bylaw.Db

Database guardrails usually become one-off ExUnit tests,
custom SQL scripts, and ad hoc error messages. Each application decides for
itself how to connect to the database, how to run checks, how to pass options,
and how to format failures.

### With Bylaw.Db

An adapter builds explicit database targets and checks implement
one small behaviour. The same checks can run against one repo, multiple repos,
dynamic repos, tenant-specific query sources, or any custom target an adapter
can query.

## Installation

Most applications should install a database adapter package instead of depending
on `bylaw_db` directly. For Postgres applications:

```elixir
def deps do
  [
    {:bylaw_postgres, "~> 0.1.0", only: [:dev, :test]}
  ]
end
```

`bylaw_postgres` depends on `bylaw_db` for the shared contracts.

Depend on `bylaw_db` directly when you are implementing a custom database
adapter, a reusable check family, or checks that intentionally work across
multiple adapters:

```elixir
def deps do
  [
    {:bylaw_db, "~> 0.1.0"}
  ]
end
```

## Usage

The common application workflow is:

1. Configure an adapter and the checks your database must satisfy.
2. Add an ExUnit test that calls the adapter's validation entrypoint.
3. Let CI fail when the migrated test database drifts from those rules.

For example, a Postgres application can configure checks in `config/test.exs`:

```elixir
import Config

config :bylaw_postgres, Bylaw.Db.Adapters.Postgres,
  repo: MyApp.Repo,
  checks: [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
    Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes,
    {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
     rules: [
       [
         where: [schema: "public"],
         columns: ["tenant_id", "inserted_at"],
         except: [[table: "schema_migrations"]]
       ]
     ]}
  ]
```

Then call validation from a database schema test:

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

`Postgres.validate/0` reads the configured repo and checks, builds a database
target, and delegates to `Bylaw.Db.validate/2`.

### Running checks against multiple targets

A target is one database or query source that checks can inspect. Targets are
passed as a list because the same checks often need to protect more than one
database boundary.

```elixir
alias Bylaw.Db
alias Bylaw.Db.Adapters.Postgres

targets = [
  Postgres.target(repo: MyApp.Repo, meta: %{name: :primary}),
  Postgres.target(repo: MyApp.AnalyticsRepo, meta: %{name: :analytics})
]

checks = [
  Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
  Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
]

assert :ok = Db.validate(targets, checks)
```

Each check runs independently against each target. `Bylaw.Db.validate/2` returns
`:ok` when all targets pass, or `{:error, issues}` when any check finds a
problem. Each issue is a `Bylaw.Db.Issue` struct.

```elixir
case Db.validate(targets, checks) do
  :ok ->
    :ok

  {:error, issues} ->
    flunk(Bylaw.Db.Issue.format_many(issues))
end
```

## Implementing custom checks

A check implements `Bylaw.Db.Check`. It receives one target and the options from
the check spec.

This example rejects tables in the public schema that do not have a primary key.

```elixir
defmodule MyApp.DatabaseChecks.RequirePrimaryKeys do
  @behaviour Bylaw.Db.Check

  alias Bylaw.Db.Issue

  @impl Bylaw.Db.Check
  def validate(target, opts) do
    schema = Keyword.get(opts, :schema, "public")

    sql = """
    SELECT c.relname AS table_name
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    LEFT JOIN pg_index i ON i.indrelid = c.oid AND i.indisprimary
    WHERE c.relkind = 'r'
      AND n.nspname = $1
      AND i.indexrelid IS NULL
    ORDER BY c.relname
    """

    case target.adapter.query(target, sql, [schema], []) do
      {:ok, result} ->
        result
        |> rows()
        |> Enum.map(&primary_key_issue(target, schema, &1))
        |> result()

      {:error, reason} ->
        {:error, [query_issue(target, schema, reason)]}
    end
  end

  defp rows(%{rows: rows}), do: rows

  defp primary_key_issue(target, schema, [table]) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "table #{schema}.#{table} does not have a primary key",
      meta: %{schema: schema, table: table}
    }
  end

  defp query_issue(target, schema, reason) do
    %Issue{
      check: __MODULE__,
      target: target,
      message: "could not inspect primary keys in schema #{schema}",
      meta: %{schema: schema, reason: reason}
    }
  end

  defp result([]), do: :ok
  defp result(issues), do: {:error, issues}
end
```

Add the check to your adapter configuration:

```elixir
config :bylaw_postgres, Bylaw.Db.Adapters.Postgres,
  repo: MyApp.Repo,
  checks: [
    {MyApp.DatabaseChecks.RequirePrimaryKeys, schema: "public"}
  ]
```

Then run it through the same test entrypoint:

```elixir
test "database structure satisfies Bylaw checks" do
  assert :ok = Bylaw.Db.Adapters.Postgres.validate()
end
```

Checks should return only `:ok` or `{:error, non_empty_issues}`. Invalid check
results raise `ArgumentError`, which keeps broken checks from silently passing.

## Implementing adapters

Database adapter packages implement `Bylaw.Db.Adapter`. An adapter is
responsible for:

- building `Bylaw.Db.Target` structs from adapter-specific options
- validating adapter-specific target shape
- executing introspection queries for checks
- delegating final check execution to `Bylaw.Db.validate/2`

The core delegation usually looks like this:

```elixir
defmodule MyAdapter do
  @behaviour Bylaw.Db.Adapter

  alias Bylaw.Db.Target

  @impl Bylaw.Db.Adapter
  def target(opts) do
    %Target{
      adapter: __MODULE__,
      repo: Keyword.fetch!(opts, :repo),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  @impl Bylaw.Db.Adapter
  def validate(targets, checks) do
    Bylaw.Db.validate(targets, checks)
  end

  @impl Bylaw.Db.Adapter
  def query(target, sql, params, opts) do
    MyAdapter.SQL.query(target.repo, sql, params, opts)
  end
end
```
