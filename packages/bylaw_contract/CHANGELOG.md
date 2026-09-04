# Changelog

## 0.1.0 - 2026-09-04

Initial package migration.

- Add test-time observation of deterministic input classes derived from specs.
- Add independent observation of exact finite-range boundary values.
- Add observation of alternatives declared by top-level return unions.
- Add source-aware structural clause and callable-arity gap reporting.
- Keep unsupported alternatives explicit instead of reporting false misses.
- Use isolated trace sessions on Erlang/OTP 27 and newer.
