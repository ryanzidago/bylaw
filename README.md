# Bylaw

Bylaw is an Elixir library for validating code, database, query, schema, and
workflow constraints.

Bylaw is organized as independent packages under `packages/`:

- `packages/bylaw_core` defines shared core helpers used by Bylaw packages.
- `packages/bylaw_ecto_query` validates prepared Ecto queries.
- `packages/bylaw_db` defines generic database check contracts and data
  structures.
- `packages/bylaw_postgres` validates Postgres database structure and schema
  conventions.
- `packages/bylaw_credo` provides custom Credo checks for downstream
  development and test environments.

## Installation

Add the package you need to your dependencies:

```elixir
def deps do
  [
    {:bylaw_ecto_query, "~> 0.1.0-alpha.1"},
    {:bylaw_postgres, "~> 0.1.0-alpha.1"},
    {:bylaw_credo, "~> 0.1.0", only: [:dev, :test], runtime: false}
  ]
end
```

## Development

Each package has its own `mix.exs`. Run package-specific commands from the
package directory:

```sh
cd packages/bylaw_ecto_query
mix test
```

To run the standard checks across all packages from the repository root:

```sh
scripts/qa.sh
```
