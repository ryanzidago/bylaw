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
    Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability,
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

### Consumer test integration

Database checks are best treated as test-environment contract checks in the
consuming application. The test database is regularly dropped and recreated, so
it reflects the current branch's migrations without stale schema objects from
unrelated development work. A long-lived dev database can be polluted by other
branches or experiments, which makes database-shape checks noisy for reasons
unrelated to the code under test.

Configure the target and checks in `config/test.exs`, after the application has
a normal Ecto SQL repo and Postgres driver available:

```elixir
config :bylaw, Bylaw.Db.Adapters.Postgres,
  repo: MyApp.Repo,
  checks: [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints,
    {Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability,
     except: [[table: "runs", column: "assistant_message_id"]]},
    Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes,
    {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
     rules: [
       [
         where: [[schema: "public"]],
         columns: ["tenant_id"]
       ]
     ],
     except: [[table: "schema_migrations"]]}
  ]
```

Then add one ExUnit test that runs after the test database has been created and
migrated:

```elixir
defmodule MyApp.BylawDbTest do
  use ExUnit.Case, async: false

  test "database structure satisfies Bylaw checks" do
    assert :ok = Bylaw.Db.Adapters.Postgres.validate()
  end
end
```

If the application wants clearer failure output, keep the formatting local to
the test:

```elixir
defmodule MyApp.BylawDbTest do
  use ExUnit.Case, async: false

  test "database structure satisfies Bylaw checks" do
    case Bylaw.Db.Adapters.Postgres.validate() do
      :ok -> :ok
      {:error, issues} -> flunk(format_issues(issues))
    end
  end

  defp format_issues(issues) do
    issues
    |> Enum.map_join("\n", fn issue ->
      "#{inspect(issue.check)}: #{issue.message} #{inspect(issue.meta)}"
    end)
  end
end
```

This keeps database-shape validation close to migrations and schema changes
without running catalog queries in production request paths.
