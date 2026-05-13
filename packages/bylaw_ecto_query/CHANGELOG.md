# Changelog

## 0.2.0 - 2026-05-13

- Add a universal scoped `rules:` DSL for every built-in Ecto query check.
  Shared scope keys are `where:` and `except:`; check-specific rule options are
  documented per check.
- Simplify `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys` and
  `Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates` to use `rules:` as
  their only public configuration entry point.
- Standardize check-specific rule options on explicit keys: `fields:`,
  `keys:`, and `match:` where accepted by the check.
- Support both single-rule shorthand (`rules: [fields: [...]]`) and scoped
  multi-rule configurations.
- Remove the older asymmetric configuration forms, including top-level `keys:`,
  top-level `fields:`, and `schemas:`.

## 0.1.0 - 2026-05-11

Initial package release.

- Add the `Bylaw.Ecto.Query` check family for validating prepared Ecto queries.
- Add built-in query checks for ordering, bounded writes, joins, visibility predicates, tenant keys, temporal comparisons, and related query constraints.
- Add HexDocs guides for query-check setup, available checks, options, issue metadata, and static analysis boundaries.
- Omit issue metadata from formatted query issue output by default, with
  `meta: true` for verbose debugging.
