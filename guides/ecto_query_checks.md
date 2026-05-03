# Bylaw.Ecto.Query Checks

`Bylaw.Ecto.Query` is the current public check family. These checks validate
prepared `Ecto.Query` structs before the repo runs them.

Each check is intentionally small, directly callable, and documented as its own
module under `Bylaw.Ecto.Query.Checks`. Use each module page for rule-specific
examples, accepted query shapes, limitations, and issue metadata.

## Running Query Checks

Query checks implement `Bylaw.Ecto.Query.Check`. For repo-wide enforcement,
run them with `Bylaw.Ecto.Query.validate/3` from Ecto's
`c:Ecto.Repo.prepare_query/3` callback.

Read the `c:Ecto.Repo.prepare_query/3` docs before copying this into a repo.
Ecto invokes the callback for query APIs, including association and preload
queries, so choose the final check list deliberately.

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @bylaw [
    Bylaw.Ecto.Query.Checks.RequiredOrder,
    Bylaw.Ecto.Query.Checks.DeterministicOrder,
    Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates,
    Bylaw.Ecto.Query.Checks.ConflictingWherePredicates
  ]

  @impl Ecto.Repo
  def prepare_query(operation, query, opts) do
    case Bylaw.Ecto.Query.validate(operation, query, @bylaw) do
      :ok -> {query, opts}
      {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
    end
  end
end
```

Checks are enabled by default once they are included in `@bylaw`. A check spec
is either a check module or `{check_module, opts}`. Each check module may appear
at most once; duplicate modules raise `ArgumentError`.

```elixir
@bylaw [
  Bylaw.Ecto.Query.Checks.RequiredOrder,
  {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys, keys: [:organisation_id]}
]
```

If callers need per-query behavior, build a duplicate-free final check list
before calling `Bylaw.Ecto.Query.validate/3`.

## Dev/Test-Only Integration

If Bylaw is declared only for `:dev` and `:test`, production-compiled modules
must not reference Bylaw modules or structs outside a compile-time guard:

```elixir
{:bylaw, "~> 0.1.0", only: [:dev, :test], runtime: false}
```

Keep every Bylaw reference inside the guarded branch:

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @impl Ecto.Repo
  def prepare_query(operation, query, opts) do
    validate_bylaw_query!(operation, query)
    {query, opts}
  end

  if System.get_env("BYLAW_VALIDATE_QUERIES") in ["1", "true"] and
       Code.ensure_loaded?(Bylaw.Ecto.Query) do
    @bylaw [
      Bylaw.Ecto.Query.Checks.RequiredOrder,
      Bylaw.Ecto.Query.Checks.DeterministicOrder
    ]

    defp validate_bylaw_query!(operation, query) do
      case Bylaw.Ecto.Query.validate(operation, query, @bylaw) do
        :ok -> :ok
        {:error, issues} -> raise Bylaw.Ecto.Query.Issue.format_many(issues)
      end
    end
  else
    defp validate_bylaw_query!(_operation, _query), do: :ok
  end
end
```

Do not put `alias Bylaw...`, `%Bylaw...{}` struct expansion, module attributes
containing Bylaw modules, or direct Bylaw calls outside that guard when the
dependency is absent in production.

The `BYLAW_VALIDATE_QUERIES` variable is read while compiling `MyApp.Repo`, not
as a release runtime toggle.

## Available Query Checks

- `Bylaw.Ecto.Query.Checks.CartesianJoins`

  Required config: none

  Catches explicit cartesian joins, including `cross_join`, uncorrelated
  `cross_lateral_join`, and non-association joins whose `on` expression is
  literally `true`.

- `Bylaw.Ecto.Query.Checks.ConflictingWherePredicates`

  Required config: none

  Catches impossible root predicates such as `status == :draft` and
  `status == :published` in the same satisfiable branch.

- `Bylaw.Ecto.Query.Checks.DateDatetimeMixedComparisons`

  Required config: none

  Catches direct comparisons between `:date` fields and datetime fields without
  an explicit date truncation or cast.

- `Bylaw.Ecto.Query.Checks.DeterministicOrder`

  Required config: none

  Catches ordered queries that do not include every root primary key field as a
  deterministic tie-breaker.

- `Bylaw.Ecto.Query.Checks.DuplicateJoins`

  Required config: none

  Catches repeated equivalent joins that can multiply result rows.

- `Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates`

  Required config: `schemas: [{Schema, fields: fields}]`

  Catches queries against configured schemas that do not explicitly mention
  visibility-sensitive fields such as `:deleted_at`, `:archived_at`, `:status`,
  or `:published_at`.

- `Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals`

  Required config: optional `fields: fields`

  Catches temporal lower bounds written with `>` and upper bounds written with
  `<=` instead of half-open `>=` and `<` boundaries.

- `Bylaw.Ecto.Query.Checks.HardDeleteOnSoftDeleteSchema`

  Required config: none

  Catches `delete_all` operations against root schemas that declare persisted
  soft-delete fields such as `:deleted_at` or `:archived_at`.

- `Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates`

  Required config: none

  Catches `where` predicates on `left_join` bindings that usually turn optional
  joins into inner joins.

- `Bylaw.Ecto.Query.Checks.MandatoryJoinKeys`

  Required config: `keys: fields`

  Catches explicit schema joins whose `on` clauses do not preserve configured
  key fields such as tenant or account ids.

- `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys`

  Required config: `keys: fields`

  Catches root queries that do not constrain configured key fields in supported
  `where` predicates.

- `Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssoc`

  Required config: none

  Catches explicit schema joins that duplicate a relationship already declared
  as an association on the query root schema.

- `Bylaw.Ecto.Query.Checks.NamedBindings`

  Required config: none

  Catches root or join bindings without `:as` aliases, plus positional field
  references in query expressions.

- `Bylaw.Ecto.Query.Checks.OffsetWithoutLimit`

  Required config: none

  Catches queries that use `offset` without `limit`, including nested subqueries
  and combination branches.

- `Bylaw.Ecto.Query.Checks.RequiredOrder`

  Required config: none

  Catches queries with `limit`, `offset`, or stream operations that do not
  include `order_by`.

- `Bylaw.Ecto.Query.Checks.UnboundedDeletes`

  Required config: none

  Catches `delete_all` queries where any possible root branch has no
  non-literal-true `where` predicate.

- `Bylaw.Ecto.Query.Checks.UnboundedUpdates`

  Required config: none

  Catches `update_all` queries that do not include at least one non-literal-true
  root `where` predicate.

- `Bylaw.Ecto.Query.Checks.UtcDatetimeNaiveComparisons`

  Required config: optional `fields: fields`

  Catches UTC datetime fields compared against `NaiveDateTime` values.

## Suggested Starting Set

One conservative starting set is:

```elixir
@bylaw [
  Bylaw.Ecto.Query.Checks.RequiredOrder,
  Bylaw.Ecto.Query.Checks.DeterministicOrder,
  Bylaw.Ecto.Query.Checks.CartesianJoins,
  Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates,
  Bylaw.Ecto.Query.Checks.ConflictingWherePredicates
]
```

No check-specific configuration is required for these checks.

Other zero-config checks can be added when the matching risk matters for the
application:

```elixir
@bylaw [
  Bylaw.Ecto.Query.Checks.DateDatetimeMixedComparisons,
  Bylaw.Ecto.Query.Checks.DuplicateJoins,
  Bylaw.Ecto.Query.Checks.HardDeleteOnSoftDeleteSchema,
  Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssoc,
  Bylaw.Ecto.Query.Checks.OffsetWithoutLimit,
  Bylaw.Ecto.Query.Checks.UnboundedDeletes,
  Bylaw.Ecto.Query.Checks.UnboundedUpdates
]
```

Then add configured checks where the application has clear invariants:

```elixir
@bylaw [
  {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
    keys: [:organisation_id],
    match: :any
  },
  {Bylaw.Ecto.Query.Checks.MandatoryJoinKeys,
    keys: [:organisation_id],
    match: :all
  },
  {Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
    schemas: [
      {Post, fields: [:deleted_at, :status]},
      {Comment, fields: [:deleted_at]}
    ]
  },
  {Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals,
    fields: [:inserted_at, :occurred_at]
  }
]
```

`Bylaw.Ecto.Query.Checks.NamedBindings` is useful for teams that want query
roots and joins to declare Ecto named binding aliases. It accepts normal Ecto
named binding list usage such as `[post: post]`, and does not require field
references to be written with `as(:post)`.

## Option Reference

### Common option

All built-in query checks accept:

| Option | Default | Meaning |
| --- | --- | --- |
| `:validate` | `true` | Set to `false` to skip this check spec in the final check list. |

### Configured checks

Some checks need application-specific fields before they can enforce anything
useful:

| Check | Option | Default | Meaning |
| --- | --- | --- | --- |
| `ExplicitVisibilityPredicates` | `:schemas` | `[]` | List of `{schema, fields: fields}` tuples. The check is a no-op for schemas that are not configured. |
| `HalfOpenTemporalIntervals` | `:fields` | Reflected temporal schema fields | Optional non-empty list of root fields to validate. Schema-less queries need this option. |
| `MandatoryJoinKeys` | `:keys` | Required | Non-empty list of join key fields to preserve in explicit schema joins. |
| `MandatoryJoinKeys` | `:match` | `:any` | Use `:any` to require at least one configured key, or `:all` to require every applicable key. |
| `MandatoryWhereKeys` | `:keys` | Required | Non-empty list of root fields that must appear in supported `where` predicates. |
| `MandatoryWhereKeys` | `:match` | `:any` | Use `:any` to require at least one configured key, or `:all` to require every applicable key. |

## Issue Results

`Bylaw.Ecto.Query.validate/3` returns `:ok` or `{:error, issues}`. Individual
checks use the same return shape. `issues` is a non-empty list of
`Bylaw.Ecto.Query.Issue` structs with:

| Field | Meaning |
| --- | --- |
| `:check` | The check module that produced the issue. |
| `:message` | Human-readable summary of the violation. |
| `:meta` | Structured data such as operation, fields, missing keys, binding indexes, or detected predicates. |

Some checks can return multiple issues when a query violates the same rule in
multiple places.

Use `Bylaw.Ecto.Query.Issue.format/1` or
`Bylaw.Ecto.Query.Issue.format_many/1` for human-readable output.

## Ecto Query Opacity

Bylaw query checks inspect prepared Ecto query structs. Ecto treats those
structs as opaque, so this is an intentional tradeoff rather than a public Ecto
API guarantee.

The tradeoff is useful in practice:

- Ecto's query structure has been fairly stable across releases.
- If Ecto changes a query shape that Bylaw depends on, the affected code is
  isolated in small checks and introspection helpers.
- Bylaw is mostly meant to run in test and development environments, so a
  breaking Ecto change should usually fail early instead of affecting
  production traffic.
- The checks catch real query problems that are difficult to enforce from
  public query APIs alone.

In general, query checks trust direct root or join field references in
supported Ecto query expressions. They intentionally avoid proving behavior
hidden inside raw SQL fragments, arbitrary functions, dynamic expressions, or
subqueries unless a specific check documents that support.
