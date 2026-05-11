# Changelog

## 0.1.0 - 2026-05-11

Initial package release.

- Add the `Bylaw.Ecto.Query` check family for validating prepared Ecto queries.
- Add built-in query checks for ordering, bounded writes, joins, visibility predicates, tenant keys, temporal comparisons, and related query constraints.
- Add HexDocs guides for query-check setup, available checks, options, issue metadata, and static analysis boundaries.
- Omit issue metadata from formatted query issue output by default, with
  `meta: true` for verbose debugging.
