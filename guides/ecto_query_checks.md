# Bylaw.Ecto.Query Checks

`Bylaw.Ecto.Query` is the current public check family. These checks validate
prepared `Ecto.Query` structs before the repo runs them.

Each check is intentionally small, directly callable, and documented as its own
module under `Bylaw.Ecto.Query.Checks`. Use each module page for rule-specific
examples, accepted query shapes, limitations, and issue metadata.

## Repo Integration

Query checks implement `Bylaw.Ecto.Query.Check`. For repo-wide enforcement,
run them with `Bylaw.Ecto.Query.validate/3` from Ecto's
`c:Ecto.Repo.prepare_query/3` callback.

Recommended dependency:

```elixir
{:bylaw, "~> 0.1.0"}
```

Enable validation in the environments where you want checks to run:

```elixir
# config/dev.exs and config/test.exs
config :my_app, :bylaw, validate_ecto_queries?: true

# config/prod.exs
config :my_app, :bylaw, validate_ecto_queries?: false
```

Keep Bylaw as a normal dependency for repo integration. The production config
above keeps query checks disabled unless you explicitly turn them on.

Start with the checks you want to enforce. When validation is enabled, pass
that list to `Bylaw.Ecto.Query.validate/3`.

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @query_checks [
    Bylaw.Ecto.Query.Checks.RequiredOrder
  ]

  @validate_ecto_queries? Application.compile_env(
                            :my_app,
                            [:bylaw, :validate_ecto_queries?],
                            false
                          )

  @impl Ecto.Repo
  def prepare_query(operation, query, opts) do
    if @validate_ecto_queries? do
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
end
```

Bylaw returns structured issues, so production users can choose a different
failure mode. For example, set `:validate_ecto_queries?` to `true` in
production and replace the `raise` branch with logging or telemetry.

Checks are enabled by default once they are included in the check list. A check
spec is either a check module or `{check_module, opts}`. Each check module may
appear at most once; duplicate modules raise `ArgumentError`.

```elixir
[
  Bylaw.Ecto.Query.Checks.RequiredOrder,
  {Bylaw.Ecto.Query.Checks.MandatoryWhereKeys, keys: [:organisation_id]}
]
```

If callers need per-query behavior, build a duplicate-free final check list
before calling `Bylaw.Ecto.Query.validate/3`.

Ecto invokes `prepare_query/3` for association and preload queries. Start
without special handling. If generated preload queries create noise, keep that
coupling isolated; Ecto currently tags them with the internal option
`Keyword.get(opts, :ecto_query) == :preload`.

## Available Query Checks

- `Bylaw.Ecto.Query.Checks.CartesianJoins`

  Required config: none

  Catches explicit cartesian joins, including `cross_join`, uncorrelated
  `cross_lateral_join`, and non-association joins whose `on` expression is
  literally `true`. The check treats lateral joins as constrained when the
  right side has an Ecto-visible dependency on a prior binding. It does not
  parse SQL fragments; a parent reference inside a lateral fragment is
  dependency evidence, not proof of exact SQL cardinality.

- `Bylaw.Ecto.Query.Checks.ConflictingWherePredicates`

  Required config: none

  Catches impossible root predicates such as `status == :draft` and
  `status == :published` in the same satisfiable branch. Empty `in` predicates
  are handled separately by `Bylaw.Ecto.Query.Checks.EmptyInPredicates`.

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

- `Bylaw.Ecto.Query.Checks.EmptyInPredicates`

  Required config: none

  Catches root `where` predicates such as `id in ^[]` where every possible
  branch has an empty `in` candidate list and the caller could return `[]`
  before querying the database.

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

- `Bylaw.Ecto.Query.Checks.HasManyJoinWithoutDistinct`

  Required config: none

  Catches top-level root-row read queries that directly join `has_many` or
  `many_to_many` associations without an obvious `distinct`, `group_by`, or
  preload assembly. It is intentionally an educational guardrail and does not
  analyze nested subqueries, CTEs, or set operations.

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
[
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
[
  Bylaw.Ecto.Query.Checks.DateDatetimeMixedComparisons,
  Bylaw.Ecto.Query.Checks.DuplicateJoins,
  Bylaw.Ecto.Query.Checks.EmptyInPredicates,
  Bylaw.Ecto.Query.Checks.HardDeleteOnSoftDeleteSchema,
  Bylaw.Ecto.Query.Checks.ManualJoinInsteadOfAssoc,
  Bylaw.Ecto.Query.Checks.OffsetWithoutLimit,
  Bylaw.Ecto.Query.Checks.UnboundedDeletes,
  Bylaw.Ecto.Query.Checks.UnboundedUpdates
]
```

Then add configured checks where the application has clear invariants:

```elixir
[
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

This is a check-spec option, not a repo option passed by callers.

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

For example, `Bylaw.Ecto.Query.Checks.CartesianJoins` uses the Ecto-visible
dependency graph to detect obvious cartesian joins. A lateral fragment that
receives a previous binding as an argument is treated as correlated, but Bylaw
does not inspect the raw SQL to prove whether that fragment returns one row,
many rows, or only rows related to the parent. Very opaque query shapes should
still be reviewed at the application boundary or excluded from repo-wide
enforcement when the local SQL intent is clearer than the Ecto structure.
