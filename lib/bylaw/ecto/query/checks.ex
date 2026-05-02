defmodule Bylaw.Ecto.Query.Checks do
  @moduledoc """
  Documentation namespace for Bylaw's built-in Ecto query checks.

  Each check is a small module that implements `Bylaw.Ecto.Query.Check` and can
  be called directly from `c:Ecto.Repo.prepare_query/3`.

  See the [`Bylaw.Ecto.Query` checks guide](ecto_query_checks.html) for
  installation, `prepare_query/3` wiring, option keys, escape hatches, and
  guidance on which checks to enable first.

  ## Available checks

  | Check | Option key | Purpose |
  | --- | --- | --- |
  | `Bylaw.Ecto.Query.Checks.ConflictingWherePredicates` | `:conflicting_where_predicates` | Reject impossible root `where` predicates. |
  | `Bylaw.Ecto.Query.Checks.DeterministicOrder` | `:deterministic_order` | Require ordered queries to include the root primary key. |
  | `Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates` | `:explicit_visibility_predicates` | Require configured visibility fields to be constrained explicitly. |
  | `Bylaw.Ecto.Query.Checks.HalfOpenTemporalIntervals` | `:half_open_temporal_intervals` | Require root temporal range predicates to be half-open. |
  | `Bylaw.Ecto.Query.Checks.LeftJoinWherePredicates` | `:left_join_where_predicates` | Reject `where` predicates that accidentally null-reject `left_join` rows. |
  | `Bylaw.Ecto.Query.Checks.MandatoryJoinKeys` | `:mandatory_join_keys` | Require explicit joins to preserve configured key fields. |
  | `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys` | `:mandatory_where_keys` | Require root `where` predicates for configured key fields. |
  | `Bylaw.Ecto.Query.Checks.NamedBindings` | `:named_bindings` | Require named Ecto bindings and named field references. |
  | `Bylaw.Ecto.Query.Checks.RequiredOrder` | `:required_order` | Require `order_by` for query shapes that depend on stable row order. |
  """
end
