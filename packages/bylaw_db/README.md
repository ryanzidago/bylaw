# Bylaw.Db

Generic database validation contracts and result data structures for Bylaw.

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
