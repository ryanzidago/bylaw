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

## Rules DSL

Every built-in check accepts the same `rules:` DSL. A bare module applies the
check globally with its default behavior:

```elixir
@query_checks [
  Bylaw.Ecto.Query.Checks.RequiredOrder
]
```

Use `{Check, rules: [...]}` to run a check only when at least one rule matches.
Rules use shared scope keys and check-specific payload keys side by side:

```elixir
@query_checks [
  {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
   rules: [fields: [:organization_id]]},
  {Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
   rules: [
     [where: [ecto_schemas: [Post]], fields: [:deleted_at, :archived_at]],
     [where: [tables: ["comments"]], fields: [:deleted_at]]
   ]}
]
```

Shared scope keys:

- `where:` applies a rule when any matcher matches. Omit it for a global rule.
- `except:` suppresses a rule that would otherwise match.

Ecto query matchers use plural keys with list values: `ecto_schemas: [Post]`,
`tables: ["posts"]`, `db_schemas: ["tenant_a"]`, and `operations: [:all]`.
Matcher values can be exact values; table and database schema matchers also
accept regexes. Unknown rule keys and missing required payload keys raise
`ArgumentError` messages that name the check.

| Check | Rule payload keys |
| --- | --- |
| `CartesianJoins` | none |
| `ConflictingWherePredicates` | none |
| `DateDatetimeMixedComparisons` | none |
| `DeterministicOrder` | none |
| `DuplicateJoins` | none |
| `EmptyInPredicates` | none |
| `ExplicitVisibilityPredicates` | `fields:` |
| `HalfOpenTemporalIntervals` | optional `fields:` |
| `HardDeleteOnSoftDeleteSchema` | none |
| `LeftJoinWherePredicates` | none |
| `MandatoryJoinKeys` | `keys:`, optional `match:` |
| `MandatoryWhereKeys` | `fields:`, optional `match:` |
| `ManualJoinInsteadOfAssoc` | none |
| `NamedBindings` | none |
| `OffsetWithoutLimit` | none |
| `RequiredOrder` | none |
| `UnboundedDeletes` | none |
| `UnboundedUpdates` | none |
| `UtcDatetimeNaiveComparisons` | optional `fields:` |

Built-in checks live under `Bylaw.Ecto.Query.Checks.*`. Start with the checks
that match your application invariants; each check module documents its own
examples, notes, options, and copyable check specs.
