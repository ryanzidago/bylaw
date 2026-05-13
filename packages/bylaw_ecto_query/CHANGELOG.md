# Changelog

## 0.2.0 - 2026-05-13

- Simplify `Bylaw.Ecto.Query.Checks.MandatoryWhereKeys` and
  `Bylaw.Ecto.Query.Checks.ExplicitVisibilityPredicates` to use `rules:` as
  their only public configuration entry point.
- Standardize both checks on `fields:` as the shared rule payload name, with
  `match:` remaining available only inside `MandatoryWhereKeys` rules.
- Support both single-rule shorthand (`rules: [fields: [...]]`) and scoped
  multi-rule configurations for both checks.
- Remove the older asymmetric configuration forms, including top-level `keys:`,
  top-level `fields:`, and `schemas:`.

## 0.1.0 - 2026-05-11

Initial package release.

- Add the `Bylaw.Ecto.Query` check family for validating prepared Ecto queries.
- Add built-in query checks for ordering, bounded writes, joins, visibility predicates, tenant keys, temporal comparisons, and related query constraints.
- Add HexDocs guides for query-check setup, available checks, options, issue metadata, and static analysis boundaries.
- Omit issue metadata from formatted query issue output by default, with
  `meta: true` for verbose debugging.
