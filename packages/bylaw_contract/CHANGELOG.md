# Changelog

## Unreleased

- Report only actionable gaps in the default human-readable output, omitting
  empty and all-clear sections.
- Point each typespec-derived diagnostic to its persisted `@spec` source and
  identify the precise input class, boundary, or return alternative involved.
- Keep unassessable typespec targets, callable-arity misses, unsupported
  structural-module details, loader warnings, and aggregate summaries out of
  the default human report while retaining them for programmatic inspection.
- Prefix every human-readable finding with a stable category such as
  `Missed boundary` or `Missed return alternative`.

## 0.1.0 - 2026-09-04

Initial package migration.

- Add test-time observation of deterministic input classes derived from specs.
- Add independent observation of exact finite-range boundary values.
- Add observation of alternatives declared by top-level return unions.
- Add source-aware structural clause and callable-arity gap reporting.
- Keep unsupported alternatives explicit instead of reporting false misses.
- Use isolated trace sessions on Erlang/OTP 27 and newer.
