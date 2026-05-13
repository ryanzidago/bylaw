# Bylaw.Ecto.Query

Validate prepared `Ecto.Query` structs before they run, so invalid query
patterns are easier to catch and harder to ship.

Use `bylaw_ecto_query` to enforce application-specific query invariants, keep
queries readable and maintainable, and codify conventions around ordering,
filtering, and other query behavior. Callers choose checks explicitly and pass
them to `Bylaw.Ecto.Query.validate/3` or `Bylaw.Ecto.Query.validate/4`.

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
    {:bylaw_ecto_query, "~> 0.2.0"}
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
    case Bylaw.Ecto.Query.validate(
           operation,
           query,
           @query_checks,
           Keyword.get(opts, :bylaw, [])
         ) do
      :ok -> {query, opts}
      {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
    end
  end
end
```

### Call-site overrides

Ecto passes repo call options to `prepare_query/3`, but Bylaw only uses them
when your repo explicitly passes them to `validate/4`:

```elixir
def prepare_query(operation, query, opts) do
  case Bylaw.Ecto.Query.validate(
         operation,
         query,
         @query_checks,
         Keyword.get(opts, :bylaw, [])
       ) do
    :ok -> {query, opts}
    {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
  end
end
```

```elixir
Repo.all(query, bylaw: false)

Repo.all(query,
  bylaw: [
    {Bylaw.Ecto.Query.Checks.RequiredOrder, validate: false}
  ])

Repo.all(query,
  bylaw: [
    {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
     rules: [fields: [:account_id]]}
  ])
```

Call-site specs replace matching repo-wide specs entirely and append new checks
after unchanged repo-wide checks.

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

## Rules DSL

Every check can be scoped with `rules:`. Rule scope is shared across checks;
check-specific rule options stay specific to each check.

A bare module applies that check globally with its defaults:

```elixir
@query_checks [
  Bylaw.Ecto.Query.Checks.RequiredOrder
]
```

`{Check, rules: [...]}` runs the check only when at least one rule scope
matches. A single global rule can use the shorthand keyword form:

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

Scope keys are the same for every check:

| Key | Meaning |
| --- | --- |
| `where:` | Run the rule when at least one matcher matches. Omitted `where:` means the rule applies globally. |
| `except:` | Suppress the rule when at least one matcher matches, even if `where:` also matches. |

Matchers use plural keys with list values:

```elixir
rules: [
  where: [
    ecto_schemas: [Post],
    tables: ["posts"],
    db_schemas: ["public"],
    operations: [:all, :stream]
  ]
]
```

Checks with no check-specific rule options accept only shared scope keys and
`validate: false` inside rules. Checks with required rule options validate
those options only for matching rules, so non-matching scoped rules do not need
to be valid for the current query. Top-level `validate: false` is a check spec
option that disables the whole check, especially when passed through call-site
overrides. Rule-level `validate: false` disables only that rule.

Built-in checks live under `Bylaw.Ecto.Query.Checks.*`. Start with the checks
that match your application invariants; each check module documents its own
examples, notes, options, and copyable rule examples.
