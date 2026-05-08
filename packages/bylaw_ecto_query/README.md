# Bylaw.Ecto.Query

Ecto query validation APIs and checks for Bylaw.

Use this package to validate prepared `Ecto.Query` structs before they run,
usually from `c:Ecto.Repo.prepare_query/3`.

## Installation

Add `:bylaw_ecto_query` to your dependencies:

```elixir
def deps do
  [
    {:bylaw_ecto_query, "~> 0.1.0"}
  ]
end
```

## Usage

Choose the query checks you want to enforce, then call
`Bylaw.Ecto.Query.validate/3`.

```elixir
checks = [
  Bylaw.Ecto.Query.Checks.RequiredOrder,
  Bylaw.Ecto.Query.Checks.DeterministicOrder,
  {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys, keys: [:organisation_id]}
]

case Bylaw.Ecto.Query.validate(:all, query, checks) do
  :ok -> :ok
  {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
end
```

For repo-wide validation, call the same function from
`c:Ecto.Repo.prepare_query/3`:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @query_checks [
    Bylaw.Ecto.Query.Checks.RequiredOrder,
    Bylaw.Ecto.Query.Checks.DeterministicOrder
  ]

  @impl Ecto.Repo
  def prepare_query(operation, query, opts) do
    case Bylaw.Ecto.Query.validate(operation, query, @query_checks) do
      :ok -> {query, opts}
      {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
    end
  end
end
```

See the HexDocs guide for environment configuration, the full built-in check
list, check options, and issue metadata.

## Built-in checks

Built-in checks live under `Bylaw.Ecto.Query.Checks.*`. Start with the checks
that match your application invariants; each check module documents its own
query shapes, options, and issue metadata.

Common zero-config checks include:

- `Bylaw.Ecto.Query.Checks.RequiredOrder`
- `Bylaw.Ecto.Query.Checks.DeterministicOrder`
- `Bylaw.Ecto.Query.Checks.CartesianJoins`
- `Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates`
- `Bylaw.Ecto.Query.Checks.ConflictingWherePredicates`

Configured checks include:

- `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys`
- `Bylaw.Ecto.Query.Checks.MandatoryJoinKeys`
- `Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates`
- `Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals`
