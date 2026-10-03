# Changelog

## Unreleased

- Rewrite around one idea: report the untested properties of functions (clause
  heads, guards, and `@spec` alternatives, boundaries and returns).
- Observe with counters injected at load time instead of `:trace`, so observation
  adds no processes and can no longer lose data.
- Removed the trace-based checks, the Elixir compiler inference check, the
  structural shadow-module classifier and `max_trace_queue`.
- Add `bylaw_contract: [since: revision]` (or `BYLAW_CONTRACT_SINCE`) to report only
  functions changed since a git revision.
- Add `bylaw_contract: [baseline: path]` and `BYLAW_CONTRACT_UPDATE_BASELINE=1` to
  record reviewed findings and print only new ones.
- Report a guard only when a later clause's patterns could accept a call it rejects.
- Report the properties of a module that other code replaces during observation
  (for example a test-double library) as unassessable with a warning, instead of missed.
- Report only declared alternatives: no invented "empty", "multiple" or "zero"
  partitions of a single declared type.
- Treat clauses a comprehension generates from one source line, or writes with
  `unquote`, as generated, so they get no clause or guard properties.
- The ExUnit formatter prints how many tests were excluded, skipped or failed,
  because findings reflect only the tests that ran.
