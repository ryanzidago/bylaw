# Bylaw.Ecto.Query

Validate prepared `Ecto.Query` structs before they run, so invalid query
patterns are easier to catch and harder to ship.

Use `bylaw_ecto_query` to enforce application-specific query invariants, keep
queries readable and maintainable, and codify conventions around ordering,
filtering, and other query behavior. Callers choose checks explicitly and pass
them to `Bylaw.Ecto.Query.validate/3`.

> #### Warning {: .warning}
>
> `bylaw_ecto_query` inspects prepared `%Ecto.Query{}` structs. Ecto exposes
> `Ecto.Query.t()`, but the internal shape of query expressions is not a stable
> extension API. Review and run your enabled checks when upgrading Ecto.

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

For repo-wide validation, choose the query checks you want to enforce and pass
them explicitly to `Bylaw.Ecto.Query.validate/3` from
`c:Ecto.Repo.prepare_query/3`:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @query_checks [
    Bylaw.Ecto.Query.Checks.RequiredOrder,
    Bylaw.Ecto.Query.Checks.DeterministicOrder,
    {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
     rules: [fields: [:organization_id]]},
    {Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
     rules: [
       [where: [ecto_schemas: [Post]], fields: [:deleted_at, :archived_at]],
       [where: [tables: ["comments"]], fields: [:deleted_at]]
     ]}
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

If you want to enable validation only in certain environments, gate the call
with your own application config:

```elixir
# config/dev.exs and config/test.exs
config :my_app, :bylaw, validate_ecto_queries?: true

# config/prod.exs
config :my_app, :bylaw, validate_ecto_queries?: false
```

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @query_checks [
    Bylaw.Ecto.Query.Checks.RequiredOrder,
    {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
     rules: [fields: [:organization_id]]}
  ]

  @impl Ecto.Repo
  def prepare_query(operation, query, opts) do
    if bylaw_ecto_query_enabled?() do
      validate_query!(operation, query)
    end

    {query, opts}
  end

  defp validate_query!(operation, query) do
    case Bylaw.Ecto.Query.validate(operation, query, @query_checks) do
      :ok -> :ok
      {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
    end
  end

  defp bylaw_ecto_query_enabled? do
    :my_app
    |> Application.get_env(:bylaw, [])
    |> Keyword.get(:validate_ecto_queries?, false)
  end
end
```

This config belongs to `:my_app`. `bylaw_ecto_query` does not read application
config or register checks globally.

Zero-config checks stay as bare modules:

```elixir
@query_checks [
  Bylaw.Ecto.Query.Checks.RequiredOrder
]
```

Configurable checks use `rules:` as their only public entry point. A single
global rule can use the shorthand keyword form:

```elixir
@query_checks [
  {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
   rules: [fields: [:organization_id]]}
]
```

Scoped rules use the list-of-rules form:

```elixir
@query_checks [
  {Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
   rules: [
     [where: [ecto_schemas: [Post]], fields: [:deleted_at, :archived_at]],
     [where: [tables: ["comments"]], fields: [:deleted_at]]
   ]}
]
```

Built-in checks live under `Bylaw.Ecto.Query.Checks.*`. Start with the checks
that match your application invariants; each check module documents its own
examples, notes, options, and copyable check specs.
