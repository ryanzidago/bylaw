# Checks Overview

Bylaw is organized as independent packages. `bylaw_postgres` provides the
Postgres database adapter and built-in database-structure checks.

## Related Packages

| Package | Scope |
| --- | --- |
| `bylaw_db` | Generic database check contracts and result data structures. |
| `bylaw_postgres` | Postgres adapter and database-structure checks. |

Postgres checks live under `Bylaw.Db.Adapters.Postgres.Checks` and implement
`Bylaw.Db.Check`.

## Built-in Checks

| Check | Purpose |
| --- | --- |
| `MissingForeignKeyIndexes` | Requires supporting indexes for foreign keys. |
| `MissingForeignKeyConstraints` | Flags columns that look like foreign keys but do not have constraints. |
| `ForeignKeyNullability` | Requires foreign key columns to be non-nullable. |
| `ScopedForeignKeys` | Requires tenant, workspace, or similar scope columns in scoped foreign keys. |
| `DuplicateIndexes` | Flags equivalent indexes on the same table. |
| `ForeignKeyActions` | Validates `ON DELETE` and `ON UPDATE` actions. |
| `RequiredColumns` | Requires configured columns on matching tables. |
| `PrimaryKeyType` | Requires configured primary key types. |
| `ForbiddenColumnTypes` | Flags configured column types and suggests preferred alternatives. |
| `EctoChangesetUniqueConstraints` | Requires matching `unique_constraint/3` calls for unique indexes. |
| `EctoChangesetForeignKeyConstraints` | Requires matching `foreign_key_constraint/3` calls for foreign keys. |
| `EctoChangesetCheckConstraints` | Requires matching `check_constraint/3` calls for check constraints when fields can be inferred. |

## Postgres Database Checks

Postgres database checks can be configured once in the consuming application:

```elixir
config :bylaw_postgres, Bylaw.Db.Adapters.Postgres,
  repo: MyApp.Repo,
  checks: [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints,
    Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability,
    {Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeys,
     rules: [
       [
         scope_columns: ["tenant_id", "workspace_id"],
         except: [[referenced_table: "global_settings"]]
       ]
     ]},
    Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes,
    {Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActions,
     rules: [
       [
         only: [[table: "messages"], [referenced_table: "conversations"]],
         on_delete: :cascade
       ],
       [
         only: [referenced_table: "lookup_statuses"],
         on_delete: :restrict,
         on_update: :restrict
       ]
     ]},
    {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
     rules: [
       [
         only: [
           [schema: "public", table: ~r/^orders/],
           [schema: "billing", table: ~r/^invoice_/]
         ],
         columns: ["tenant_id", "account_id"],
         except: [[table: "schema_migrations"], [schema: "public", table: "audit_log"]]
       ]
     ]},
    {Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType,
     rules: [
       [
         only: [schema: "public"],
         types: ["uuid"],
         except: [[table: "schema_migrations"]]
       ]
     ]},
    {Bylaw.Db.Adapters.Postgres.Checks.ForbiddenColumnTypes,
     rules: [
       [
         only: [schema: "public"],
         types: [
           [type: "json", prefer: "jsonb"],
           [type: "money", prefer: "numeric plus an explicit currency column"]
         ],
         except: [[table: "webhook_events", column: "raw_payload"]]
       ]
     ]},
    {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraints,
     paths: ["lib/my_app"]},
    {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetForeignKeyConstraints,
     paths: ["lib/my_app"]},
    {Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetCheckConstraints,
     paths: ["lib/my_app"]}
  ]
```

Use `ForbiddenColumnTypes` to teach project database conventions without
hard-coding Bylaw-wide opinions about which Postgres types are acceptable:

```elixir
{Bylaw.Db.Adapters.Postgres.Checks.ForbiddenColumnTypes,
 rules: [
   [
     only: [schema: "public"],
     types: [
       [
         type: "json",
         prefer: "jsonb",
         reason: "jsonb is indexable and avoids reparsing for most application queries"
       ],
       [
         type: "money",
         prefer: "numeric plus an explicit currency column",
         reason: "Postgres money is locale-sensitive and awkward to migrate"
       ]
     ],
     except: [[table: "webhook_events", column: "raw_payload"]]
   ]
 ]}
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
         only: [[schema: "tenant_one"], [schema: "tenant_two"]],
         columns: ["tenant_id"]
       ]
     ]}
  ]
)
```

Both forms return raw `Bylaw.Db.Issue` structs in `{:error, issues}`, so tests
can assert on issue metadata directly without formatting adapter code.
Use `Bylaw.Db.Issue.format_many/1` for human-readable output. The formatter
omits metadata by default; pass `meta: true` when debugging needs the full
structured metadata.

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
config :bylaw_postgres, Bylaw.Db.Adapters.Postgres,
  repo: MyApp.Repo,
  checks: [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints,
    {Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability,
     rules: [[except: [[table: "runs", column: "assistant_message_id"]]]]},
    {Bylaw.Db.Adapters.Postgres.Checks.ScopedForeignKeys,
     rules: [
       [
         scope_columns: ["tenant_id", "workspace_id"],
         except: [[referenced_table: "shared_templates"]]
       ]
     ]},
    {Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActions,
     rules: [
       [
         only: [referenced_table: "accounts"],
         on_delete: :restrict,
         on_update: :restrict
       ],
       [
         only: [table: "messages", referenced_table: "conversations"],
         on_delete: :cascade
       ]
     ]},
    Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes,
    {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
     rules: [
       [
         only: [schema: "public"],
         columns: ["tenant_id"],
         except: [[table: "schema_migrations"]]
       ]
     ]},
    {Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType,
     rules: [
       [
         only: [schema: "public"],
         types: ["uuid"],
         except: [[table: "schema_migrations"]]
       ]
     ]}
  ]
```

`Bylaw.Db.Adapters.Postgres.Checks.PrimaryKeyType` can replace
project-specific checks such as "all tables use UUID primary keys" while still
allowing scoped exceptions for migration metadata or legacy tables.

The Ecto changeset checks need source paths so Bylaw can parse conservative
changeset candidates:

```elixir
{Bylaw.Db.Adapters.Postgres.Checks.EctoChangesetUniqueConstraints,
 paths: ["lib/my_app"]}
```

When `repo.config()[:otp_app]` is available, schema discovery is inferred from
the repo. Otherwise pass `otp_app: :my_app` or
`schema_modules: [MyApp.Accounts.User, MyApp.Billing.Invoice]`.

`ScopedForeignKeys` is useful for tenant, workspace, account, or similar
scoping. If both `messages` and `conversations` have `tenant_id` and
`workspace_id`, a foreign key from `messages(conversation_id)` to
`conversations(id)` fails because it can cross scopes. Define the constraint as
`messages(tenant_id, workspace_id, conversation_id)` referencing
`conversations(tenant_id, workspace_id, id)` instead, or add an `except` matcher
for intentionally shared references.

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
      {:error, issues} -> flunk(Bylaw.Db.Issue.format_many(issues))
    end
  end
end
```

This keeps database-shape validation close to migrations and schema changes
without running catalog queries in production request paths.
