# Bylaw.Postgres

Postgres database validation adapter and checks for Bylaw.

This package owns `Bylaw.Db.Adapters.Postgres` and
`Bylaw.Db.Adapters.Postgres.Checks.*`. It depends on `bylaw_db`, `ecto_sql`, and
`postgrex`.

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

Use the HexDocs checks guide for configuration examples, the built-in check
list, and ExUnit integration.
