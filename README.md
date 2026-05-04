# Bylaw

Bylaw is an Elixir library for validating code, database, query, schema, and
workflow constraints.

Bylaw is organized around check families. The first public family is
`Bylaw.Ecto.Query`, which validates prepared Ecto queries before the repo runs
them. `Bylaw.Credo` and `Bylaw.Db` are planned families.

See the HexDocs [checks overview](https://hexdocs.pm/bylaw/checks.html) and
[`Bylaw.Ecto.Query` checks guide](https://hexdocs.pm/bylaw/ecto_query_checks.html)
for the built-in checks, check specs, `prepare_query/3` wiring, and issue
metadata.

## Installation

Add `bylaw` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:bylaw, "~> 0.1.0"}
  ]
end
```

Documentation is published on [HexDocs](https://hexdocs.pm/bylaw).
