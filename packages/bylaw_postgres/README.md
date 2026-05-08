# Bylaw.Postgres

Postgres database validation adapter and checks for Bylaw.

This package owns `Bylaw.Db.Adapters.Postgres` and
`Bylaw.Db.Adapters.Postgres.Checks.*`. It also includes Ecto helper modules used
by the changeset constraint checks.

## Installation

Add `bylaw_postgres` to applications that want Postgres database-shape
validation:

```elixir
def deps do
  [
    {:bylaw_postgres, "~> 0.1.0", only: [:dev, :test]}
  ]
end
```

`bylaw_postgres` depends on `bylaw_db`, `ecto_sql`, and `postgrex`; consuming
applications should already have an Ecto SQL repo and Postgres driver available.

## Configuration

Configure checks in `config/test.exs` or `config/dev.exs`:

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

Then run the configured checks:

```elixir
Bylaw.Db.Adapters.Postgres.validate()
```

Most projects run database-shape checks from ExUnit after the test database has
been created and migrated:

```elixir
test "database structure satisfies Bylaw checks" do
  assert :ok = Bylaw.Db.Adapters.Postgres.validate()
end
```

See the HexDocs checks guide for the built-in check list, rule options, and
Ecto changeset constraint examples.
