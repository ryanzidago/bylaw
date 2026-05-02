# Bylaw

Bylaw is an Elixir library for validating code, database, query, schema, and
workflow constraints.

The first public checks validate prepared Ecto queries before the repo runs
them. See the HexDocs [Checks guide](https://hexdocs.pm/bylaw/checks.html) for
the list of built-in checks, option keys, `prepare_query/3` wiring, and escape
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
