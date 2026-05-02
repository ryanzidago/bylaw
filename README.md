# Bylaw

Bylaw is an Elixir library for validating code, database, query, schema, and
workflow constraints.

Bylaw is organized around check families. `Bylaw.Ecto.Query` validates prepared
Ecto queries before the repo runs them, and `Bylaw.Db` validates database
structure through adapter-specific targets. `Bylaw.Credo` is planned.

See the HexDocs [checks overview](https://hexdocs.pm/bylaw/checks.html) and
[`Bylaw.Ecto.Query` checks guide](https://hexdocs.pm/bylaw/ecto_query_checks.html)
for the built-in checks, option keys, `prepare_query/3` wiring, and escape
hatches.

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `bylaw` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bylaw, "~> 0.1.0"}
  ]
end
```

Documentation is published on [HexDocs](https://hexdocs.pm/bylaw).

## Development

Postgres integration tests are tagged with `:postgres` and excluded by default.
Run them against a disposable test database with:

```sh
BYLAW_POSTGRES_URL=postgres://postgres:postgres@localhost:5432/bylaw_test \
  mix test --include postgres
```
