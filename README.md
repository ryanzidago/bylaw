# Bylaw

Bylaw is an Elixir library for validating code, database, query, schema, and
rendered HTML constraints.

Bylaw is organized as independent packages under `packages/`:

Packages most applications start with:

- [`packages/bylaw_html`](packages/bylaw_html/README.md) validates rendered
  HTML strings with explicit checks.
- [`packages/bylaw_ecto_query`](packages/bylaw_ecto_query/README.md) validates
  prepared Ecto queries.
- [`packages/bylaw_postgres`](packages/bylaw_postgres/README.md) validates
  Postgres database structure and schema conventions.
- [`packages/bylaw_credo`](packages/bylaw_credo/README.md) provides custom Credo
  checks for downstream development and test environments.

Supporting packages used by Bylaw itself:

- [`packages/bylaw_core`](packages/bylaw_core/README.md) defines shared core
  helpers used by Bylaw packages.
- [`packages/bylaw_db`](packages/bylaw_db/README.md) defines generic database
  check contracts and data structures.

## Installation

Add the package you need to your dependencies:

```elixir
def deps do
  [
    {:bylaw_html, "~> 0.1.0-alpha.1"},
    {:bylaw_ecto_query, "~> 0.1.0"},
    {:bylaw_postgres, "~> 0.1.0"},
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
