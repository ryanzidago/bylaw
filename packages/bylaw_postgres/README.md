# Bylaw.Postgres

Validate Postgres database structure and enforce schema conventions with
`bylaw_postgres`.

This package owns `Bylaw.Db.Adapters.Postgres` and
`Bylaw.Db.Adapters.Postgres.Checks.*`. It also includes Ecto helper modules used
by the changeset constraint checks.

## Installation

Add `bylaw_postgres` to applications that want Postgres schema validation:

```elixir
def deps do
  [
    {:bylaw_postgres, "~> 0.3.0", only: [:dev, :test]}
  ]
end
```

`bylaw_postgres` depends on `bylaw_db`, `ecto_sql`, and `postgrex`; consuming
applications should already have an Ecto SQL repo and Postgres driver available.

## Usage

Most projects run database-shape checks from ExUnit after the test database has
been created and migrated:

```elixir
defmodule MyApp.BylawDbTest do
  use ExUnit.Case, async: false

  alias Bylaw.Db.Adapters.Postgres

  @checks [
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyIndexes,
    Bylaw.Db.Adapters.Postgres.Checks.MissingForeignKeyConstraints,
    Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyNullability,
    Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
  ]

  test "database structure satisfies Bylaw checks" do
    assert :ok = Postgres.validate(MyApp.Repo, @checks)
  end
end
```

`Postgres.validate/2` validates one repo per call. Pass `:dynamic_repo` to
`validate/3` when a specific dynamic repo should be inspected.

```elixir
test "tenant database structure satisfies Bylaw checks" do
  assert :ok = Postgres.validate(MyApp.Repo, @checks, dynamic_repo: :tenant_one)
end
```

For multiple repos, make separate calls:

```elixir
test "database structure satisfies Bylaw checks" do
  assert :ok = Postgres.validate(MyApp.Repo, @checks)
  assert :ok = Postgres.validate(MyApp.AnalyticsRepo, @checks)
end
```

See each check module's documentation for its examples, notes, and options.

## Ecto query unique keys

`Bylaw.Db.Adapters.Postgres.UniqueKeys.fetch!/1` reads primary and conservative
unique column sets for use with
`Bylaw.Ecto.Query.Checks.DeterministicOrder`:

```elixir
defp query_checks do
  [
    {Bylaw.Ecto.Query.Checks.DeterministicOrder,
     unique_keys: fn ->
       Bylaw.Db.Adapters.Postgres.UniqueKeys.fetch!(__MODULE__)
     end}
  ]
end
```

The result is a map keyed by `{database_schema, table}`:

```elixir
%{
  {"public", "posts"} => [
    ["id"],
    ["slug"],
    ["organisation_id", "sequence"]
  ]
}
```

The helper is stateless and performs one catalogue query per invocation.
`DeterministicOrder` skips the resolver when Ecto primary-key reflection already
proves the ordering.

## Rules DSL

Every built-in check accepts the same `rules:` DSL. Checks with default behavior
can be passed as bare modules to run globally:

```elixir
@checks [
  Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
]
```

Use `{Check, rules: [...]}` when a check needs required rule options or should
run only when at least one rule matches. Rules use shared scope keys and
check-specific rule options side by side:

```elixir
@checks [
  {Bylaw.Db.Adapters.Postgres.Checks.RequiredColumns,
   rules: [columns: ["tenant_id"]]},
  {Bylaw.Db.Adapters.Postgres.Checks.ForeignKeyActions,
   rules: [
     [where: [referenced_tables: ["lookup_statuses"]], on_delete: :restrict, on_update: :restrict],
     [where: [tables: ["messages"]], except: [constraints: ["messages_status_id_fkey"]], on_delete: :cascade]
   ]},
  Bylaw.Db.Adapters.Postgres.Checks.DuplicateIndexes
]
```

Shared scope keys:

- `where:` applies a rule when any matcher matches. Omit it for a global rule.
- `except:` suppresses a rule that would otherwise match.

Postgres matchers use plural keys with non-empty list values: `schemas:`,
`tables:`, `columns:`, `constraints:`, `types:`, `referenced_schemas:`,
`referenced_tables:`, and `referenced_columns:` where supported by the check.
Matcher values can be strings or regexes. Unknown rule keys and missing required
check-specific options raise `ArgumentError` messages that name the check.
Top-level `validate: false` disables the whole check.

Checks with no check-specific rule options accept only shared scope keys inside
rules. Checks with required rule options document those options in their module
docs with copyable rule examples.

## Reviewing redundant stored facts

A table can store the same current business fact in several columns. For
example, an Offer-like table with `applies_to`, `menu_id` and `item_id` may
represent its target twice. The redundant discriminator can drift from the
foreign keys. `RedundantStoredFacts` supplies catalogue evidence to your own
review function so it can assess whether a column duplicates a fact or
preserves a deliberate historical value.

```elixir
checks = [
  {Bylaw.Db.Adapters.Postgres.Checks.RedundantStoredFacts,
   reviewer: &MyApp.SchemaReviewer.review/1,
   rules: [
     [
       where: [schemas: ["public"], tables: ["order_lines"]],
       exceptions: [
         %{columns: ["unit_price"], reason: "Preserves the agreed purchase price"}
       ]
     ],
     [
       where: [schemas: ["public"]],
       except: [tables: ["order_lines", "schema_migrations"]]
     ]
   ]}
]

assert :ok = Bylaw.Db.Adapters.Postgres.validate(MyApp.Repo, checks)
```

Your `MyApp.SchemaReviewer.review/1` receives one versioned map per selected
table: `%{version: 1, invariant: %{id: ..., version: 1, text: ...}, table: ...,
exceptions: ...}`. The documented `review_input` type describes all evidence.
The function returns exactly one of:

```elixir
{:ok, :no_violation}
{:ok, :violation}
{:ok, :justified_exception}
{:ok, :insufficient_context}
{:error, :not_configured}
{:error, :timeout}
{:error, :request_failed}
{:error, :invalid_response}
{:error, :input_too_large}
```

Only `:no_violation` and `:justified_exception` pass. Other results become
issues with distinct stable metadata for violations, uncertainty, reviewer
failures, inspection failures or invalid exception columns. Malformed returns
become `:invalid_response`. Tagged reviewer failures do not prevent review of
other selected tables. The caller handles deadlines, expected error conversion
and any provider integration; arbitrary caller exceptions propagate.

Omit `rules:` to review all current user tables. Overlapping rules produce one
call per selected table. `except:` skips that rule's matching table without a
review call unless another rule selects it. Column exceptions apply only within
their rule's scope, require existing columns and a nonblank reason, and supply
context rather than automatically waiving the table or reviewer failures.
`validate: false` performs no query or calls and needs no reviewer.

The check reads a single catalogue snapshot, including comments, ordered
columns, types, defaults, generated expressions, identity metadata, constraints
and indexes. It reads no data rows, executes no stored expressions and does not
truncate definitions. It includes direct enum labels and domain definitions,
but does not export a dependency graph, related tables, function bodies,
triggers or policies. Evidence and exception text are data, not instructions.

This is an explicit opt-in check with no model SDK, credentials, HTTP client or
automatic provider calls. It cannot prove business semantics or model
correctness. Missing business meaning should produce `:insufficient_context`.
The tests establish metadata and callback handling with fake reviewers; they
do not assess a live model's review accuracy.
