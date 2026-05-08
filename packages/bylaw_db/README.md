# Bylaw.Db

Generic database validation contracts and consumer-facing data structures for
Bylaw.

This package owns `Bylaw.Db`, `Bylaw.Db.Adapter`, `Bylaw.Db.Check`,
`Bylaw.Db.Issue`, and `Bylaw.Db.Target`. It intentionally has no Postgres or
Postgrex dependency.

## Installation

Adapter packages such as `bylaw_postgres` depend on this package directly.
Only add `bylaw_db` yourself when implementing a custom database adapter or
check family:

```elixir
def deps do
  [
    {:bylaw_db, "~> 0.1.0"}
  ]
end
```

## Usage

Adapter packages build `Bylaw.Db.Target` structs and delegate validation to
`Bylaw.Db.validate/2`:

```elixir
target = MyAdapter.target(repo: MyApp.Repo)

Bylaw.Db.validate([target], [
  {MyApp.Checks.RequiredIndexes, schemas: ["public"]}
])
```

`Bylaw.Db.validate/2` returns `:ok` or `{:error, issues}` where each issue is a
`Bylaw.Db.Issue` struct. Use `Bylaw.Db.Issue.format/1` or
`Bylaw.Db.Issue.format_many/1` for human-readable output.

## Implementing adapters and checks

Database adapter packages implement `Bylaw.Db.Adapter`. Checks implement
`Bylaw.Db.Check` and return only `:ok` or `{:error, issues}`:

```elixir
defmodule MyApp.Checks.RequiredIndexes do
  @behaviour Bylaw.Db.Check

  @impl Bylaw.Db.Check
  def validate(target, opts) do
    # Query through the target's adapter and return Bylaw.Db.Issue structs
    # when the database does not satisfy the check.
  end
end
```
