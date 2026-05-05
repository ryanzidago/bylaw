# Checks Overview

Bylaw is organized around check families. A family is a namespace that targets
one source of project rules, such as static Elixir code, database structure, or
prepared Ecto queries.

## Check Families

| Namespace | Status | Scope |
| --- | --- | --- |
| `Bylaw.Credo` | Planned | Custom Credo checks for source-code rules that should fail during static analysis. |
| `Bylaw.Db` | Available now | Database-schema checks for constraints that should be derived from the database shape. |
| `Bylaw.Ecto.Query` | Available now | Runtime checks for prepared `Ecto.Query` structs before a repo operation runs. |

The current public families are `Bylaw.Ecto.Query` and `Bylaw.Db`. Ecto query
checks live under `Bylaw.Ecto.Query.Checks` and implement
`Bylaw.Ecto.Query.Check`. Database checks live under adapter-specific namespaces
and implement `Bylaw.Db.Check`.

Use the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for the
current check list, `prepare_query/3` wiring, check specs, and issue metadata.

## Postgres Database Checks

Postgres database checks can be configured once in the consuming application:

```elixir
config :bylaw, Bylaw.Db.Adapters.Postgres,
  repo: MyApp.Repo,
  checks: [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
    Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes,
    {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
     rules: [
       [
         where: [
           [schema: "public", table: ~r/^orders/],
           [schema: "billing", table: ~r/^invoice_/]
         ],
         columns: ["tenant_id", "account_id"]
       ]
     ],
     except: [[table: "schema_migrations"], [schema: "public", table: "audit_log"]]}
  ]
```

Then run the configured checks:

```elixir
Bylaw.Db.Adapters.Postgres.validate()
```

For one-off validation, pass the same shape directly:

```elixir
Bylaw.Db.Adapters.Postgres.validate(
  repo: MyApp.Repo,
  checks: [
    {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
     rules: [
       [
         where: [[schema: "tenant_one"], [schema: "tenant_two"]],
         columns: ["tenant_id"]
       ]
     ]}
  ]
)
```

Both forms return raw `Bylaw.Db.Issue` structs in `{:error, issues}`, so tests
can assert on issue metadata directly without formatting adapter code.
