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
current check list, `prepare_query/3` wiring, option keys, escape hatches, and
issue metadata.
