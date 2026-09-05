# Changelog

## Unreleased

- Initialize check state in its owning worker, avoid duplicate typespec target
  indexes, release structural classifier ASTs, and assemble final coverage in
  the caller to reduce process-copy amplification. Preserve ordered claims and
  clean up initialized workers when startup fails.
- Keep compiler observation of its own runtime modules unassessable with an
  explicit warning, avoiding hot-reload termination of the active observer.

- Store repeated typespec aliases as compact graphs, bound alias and union
  expansion work, and stop expanding unsupported members while preserving
  input partitions and source locations.

- Preserve compiler alternatives and independent function inference when return
  union normalization absorbs or merges clause labels; keep functions without
  an exact clause mapping unassessable instead of rejecting the entire module.

- Add opt-in, checker-versioned observation of unambiguous finite return
  alternatives from Elixir 1.20's private compiler-inference BEAM chunk.
- Limit compiler-inferred runtime obligations to authored functions using
  Elixir debug metadata, excluding macro-generated exports without
  library-specific name filters.
- Isolate each private compiler-chunk decode behind a fixed per-module timeout
  so pathological descriptor expansion remains bounded and unassessable.
- Infer compiler alternatives from executed function clauses only when the
  compiler's input-to-return rules identify one unique outcome, avoiding
  runtime tracing and keeping ambiguous outcomes unassessable.
- Match unambiguous compiler rules through narrowly injected clause counters
  without enabling VM tracing, inspecting returned values, or starting the
  `:cover` server; exclude protocol implementation modules and bound
  instrumentation with a configurable function limit.
- Make typespec, structural, and Elixir compiler observation independently
  selectable through an explicit ordered list of contract check modules.
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
