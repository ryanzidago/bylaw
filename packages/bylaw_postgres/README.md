# Bylaw.Postgres

Validate Postgres database structure and enforce schema conventions with
`bylaw_postgres`.

This package owns `Bylaw.Db.Adapters.Postgres` and
`Bylaw.Db.Adapters.Postgres.Checks.*`. It also includes Ecto helper modules used
by the changeset constraint checks.

## Installation

Add `bylaw_postgres` to applications that want Postgres schema validation:

```elixir
def deps do
  [
    {:bylaw_postgres, "~> 0.1.0", only: [:dev, :test]}
  ]
end
```

`bylaw_postgres` depends on `bylaw_db`, `ecto_sql`, and `postgrex`; consuming
applications should already have an Ecto SQL repo and Postgres driver available.

## Usage

Most projects run database-shape checks from ExUnit after the test database has
been created and migrated:

```elixir
defmodule MyApp.BylawDbTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres

  @checks [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints,
    Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability,
    Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
  ]

  test "database structure satisfies Bylaw checks" do
    assert :ok = Postgres.validate(MyApp.Repo, @checks)
  end
end
```

`Postgres.validate/2` validates one repo per call. Pass `:dynamic_repo` to
`validate/3` when a specific dynamic repo should be inspected.

```elixir
test "tenant database structure satisfies Bylaw checks" do
  assert :ok = Postgres.validate(MyApp.Repo, @checks, dynamic_repo: :tenant_one)
end
```

For multiple repos, make separate calls:

```elixir
test "database structure satisfies Bylaw checks" do
  assert :ok = Postgres.validate(MyApp.Repo, @checks)
  assert :ok = Postgres.validate(MyApp.AnalyticsRepo, @checks)
end
```

See each check module's documentation for its examples, notes, and options.

## Rules DSL

Every built-in check accepts the same `rules:` DSL. A bare module applies the
check globally with its default behavior:

```elixir
@checks [
  Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
]
```

Use `{Check, rules: [...]}` to run a check only when at least one rule matches.
Rules use shared scope keys and check-specific rule options side by side:

```elixir
@checks [
  {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
   rules: [columns: ["tenant_id"]]},
  {Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActions,
   rules: [
     [where: [referenced_tables: ["lookup_statuses"]], on_delete: :restrict, on_update: :restrict],
     [where: [tables: ["messages"]], except: [constraints: ["messages_status_id_fkey"]], on_delete: :cascade]
   ]},
  Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
]
```

Shared scope keys:

- `where:` applies a rule when any matcher matches. Omit it for a global rule.
- `except:` suppresses a rule that would otherwise match.

Postgres matchers use plural keys with non-empty list values: `schemas:`,
`tables:`, `columns:`, `constraints:`, `types:`, `referenced_schemas:`,
`referenced_tables:`, and `referenced_columns:` where supported by the check.
Matcher values can be strings or regexes. Unknown rule keys and missing required
check-specific options raise `ArgumentError` messages that name the check.

| Check | Check-specific rule options |
| --- | --- |
| `DuplicateIndexes` | none |
| `EctoChangesetCheckConstraints` | none |
| `EctoChangesetForeignKeyConstraints` | none |
| `EctoChangesetUniqueConstraints` | none |
| `ForbiddenColumnTypes` | `types:` |
| `ForeignKeyActions` | `on_delete:` and/or `on_update:` |
| `ForeignKeyNullability` | none |
| `MissingForeignKeyConstraints` | none |
| `MissingForeignKeyIndexes` | none |
| `PrimaryKeyType` | `types:` |
| `RequiredColumns` | `columns:` |
| `ScopedForeignKeys` | `scope_columns:` |
