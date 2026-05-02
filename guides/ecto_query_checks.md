# Bylaw.Ecto.Query Checks

`Bylaw.Ecto.Query` is the current public check family. These checks validate
prepared `Ecto.Query` structs before the repo runs them.

Each check is intentionally small, directly callable, and documented as its own
module under `Bylaw.Ecto.Query.Checks`. Use each module page for rule-specific
examples, accepted query shapes, limitations, and issue metadata.

## Running Query Checks

Query checks implement `Bylaw.Ecto.Query.Check`. For repo-wide enforcement,
call them from Ecto's `c:Ecto.Repo.prepare_query/3` callback.

Read the `c:Ecto.Repo.prepare_query/3` docs before copying this into a repo.
Ecto invokes the callback for query APIs, including association and preload
queries, so configure query-level escape hatches deliberately.

```elixir
defmodule MyApp.Repo do
  use Ecto.Repo,
    otp_app: :my_app,
    adapter: Ecto.Adapters.Postgres

  @checks [
    Bylaw.Ecto.Query.Checks.RequiredOrder,
    Bylaw.Ecto.Query.Checks.DeterministicOrder,
    Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates,
    Bylaw.Ecto.Query.Checks.ConflictingWherePredicates
  ]

  @bylaw []

  @impl Ecto.Repo
  def prepare_query(operation, query, opts) do
    bylaw_opts =
      Keyword.merge(@bylaw, Keyword.get(opts, :bylaw, []), fn _check, default, override ->
        Keyword.merge(default, override)
      end)

    case validate_query(operation, query, bylaw_opts) do
      :ok -> {query, opts}
      {:error, issue_or_issues} -> raise inspect(issue_or_issues)
    end
  end

  defp validate_query(operation, query, bylaw_opts) do
    Enum.reduce_while(@checks, :ok, fn check, :ok ->
      case check.validate(operation, query, bylaw_opts) do
        :ok -> {:cont, :ok}
        {:error, _issue_or_issues} = error -> {:halt, error}
      end
    end)
  end
end
```

Checks are enabled by default once they are included in `@checks`. The
repo-level `@bylaw` keyword list is only needed for non-default options or
default escape hatches. Callers can override a check for a single query through
the query options:

```elixir
Repo.all(query, bylaw: [required_order: [validate: false]])
```

Every built-in query check treats `validate: false` as an explicit query-level
escape hatch.

## Available Query Checks

- `Bylaw.Ecto.Query.Checks.CartesianJoins`

  Option key: `:cartesian_joins`

  Required config: none

  Catches explicit cartesian joins, including `cross_join`, uncorrelated
  `cross_lateral_join`, and non-association joins whose `on` expression is
  literally `true`.

- `Bylaw.Ecto.Query.Checks.ConflictingWherePredicates`

  Option key: `:conflicting_where_predicates`

  Required config: none

  Catches impossible root predicates such as `status == :draft` and
  `status == :published` in the same satisfiable branch.

- `Bylaw.Ecto.Query.Checks.DeterministicOrder`

  Option key: `:deterministic_order`

  Required config: none

  Catches ordered queries that do not include every root primary key field as a
  deterministic tie-breaker.

- `Bylaw.Ecto.Query.Checks.DuplicateJoins`

  Option key: `:duplicate_joins`

  Required config: none

  Catches repeated equivalent joins that can multiply result rows.

- `Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates`

  Option key: `:explicit_visibility_predicates`

  Required config: `schemas: [{Schema, fields: fields}]`

  Catches queries against configured schemas that do not explicitly mention
  visibility-sensitive fields such as `:deleted_at`, `:archived_at`, `:status`,
  or `:published_at`.

- `Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals`

  Option key: `:half_open_temporal_intervals`

  Required config: optional `fields: fields`

  Catches temporal lower bounds written with `>` and upper bounds written with
  `<=` instead of half-open `>=` and `<` boundaries.

- `Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates`

  Option key: `:left_join_where_predicates`

  Required config: none

  Catches `where` predicates on `left_join` bindings that usually turn optional
  joins into inner joins.

- `Bylaw.Ecto.Query.Checks.MandatoryJoinKeys`

  Option key: `:mandatory_join_keys`

  Required config: `keys: fields`

  Catches explicit schema joins whose `on` clauses do not preserve configured
  key fields such as tenant or account ids.

- `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys`

  Option key: `:mandatory_where_keys`

  Required config: `keys: fields`

  Catches root queries that do not constrain configured key fields in supported
  `where` predicates.

- `Bylaw.Ecto.Query.Checks.NamedBindings`

  Option key: `:named_bindings`

  Required config: none

  Catches root or join bindings without `:as` aliases, plus positional field
  references in query expressions.

- `Bylaw.Ecto.Query.Checks.RequiredOrder`

  Option key: `:required_order`

  Required config: none

  Catches queries with `limit`, `offset`, or stream operations that do not
  include `order_by`.

- `Bylaw.Ecto.Query.Checks.UtcDatetimeNaiveComparisons`

  Option key: `:utc_datetime_naive_comparisons`

  Required config: optional `fields: fields`

  Catches UTC datetime fields compared against `NaiveDateTime` values.

## Suggested Starting Set

Start with checks that do not require application-specific configuration:

```elixir
@checks [
  Bylaw.Ecto.Query.Checks.RequiredOrder,
  Bylaw.Ecto.Query.Checks.DeterministicOrder,
  Bylaw.Ecto.Query.Checks.CartesianJoins,
  Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates,
  Bylaw.Ecto.Query.Checks.ConflictingWherePredicates
]
```

No `@bylaw` configuration is required for these checks.

Then add configured checks where the application has clear invariants:

```elixir
@checks [
  Bylaw.Ecto.Query.Checks.MandatoryWhereKeys,
  Bylaw.Ecto.Query.Checks.MandatoryJoinKeys,
  Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates,
  Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals
]

@bylaw [
  mandatory_where_keys: [
    keys: [:organisation_id],
    match: :any
  ],
  mandatory_join_keys: [
    keys: [:organisation_id],
    match: :all
  ],
  explicit_visibility_predicates: [
    schemas: [
      {Post, fields: [:deleted_at, :status]},
      {Comment, fields: [:deleted_at]}
    ]
  ],
  half_open_temporal_intervals: [
    fields: [:inserted_at, :occurred_at]
  ]
]
```

`Bylaw.Ecto.Query.Checks.NamedBindings` is useful for teams that want every
query expression to use Ecto named bindings. It is stricter than the other
checks because it is a style and maintainability rule as much as a correctness
rule, so it is often easiest to enable after existing query code has been
cleaned up.

## Option Reference

### Common option

All built-in query checks accept:

| Option | Default | Meaning |
| --- | --- | --- |
| `:validate` | `true` | Set to `false` to skip the check for a specific repo default or query call. |

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

Query checks return `:ok` or `{:error, issue_or_issues}`. Issues are
`Bylaw.Ecto.Query.Issue` structs with:

| Field | Meaning |
| --- | --- |
| `:check` | The check module that produced the issue. |
| `:message` | Human-readable summary of the violation. |
| `:meta` | Structured data such as operation, fields, missing keys, binding indexes, or detected predicates. |

Some checks can return multiple issues when a query violates the same rule in
multiple places.

## Static Analysis Boundaries

Bylaw query checks inspect prepared Ecto query structs. Ecto treats those
structs as opaque, so each check supports a small, tested subset of Ecto's
query AST.

In general, query checks trust direct root or join field references in
supported Ecto query expressions. They intentionally avoid proving behavior
hidden inside raw SQL fragments, arbitrary functions, dynamic expressions, or
subqueries unless a specific check documents that support.
