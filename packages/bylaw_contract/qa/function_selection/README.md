# Explicit function selection QA

`Bylaw.Contract.start(modules, only: mfas)` must narrow obligations before check
initialization without changing selected-function results, counters, unknown
outcomes, or restoration. `probe.exs` compares unscoped observation with three
scoped runs for each built-in check, using existing compiled code from approved
QA repositories. Each run makes four calls in the caller and four in a child
Task. It also verifies an explicit empty selection creates no check workers.

These are focused real-module probes, not full application test-suite runs.

| Repository | Revision | Function |
| --- | --- | --- |
| Ecto | `11784f821a1bb0eedeee59583e311d836cb39ee1` | `Ecto.UUID.cast/1` |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | `Livebook.Text.Delta.Operation.from_compressed/1` |

Run from `packages/bylaw_contract`, using Elixir 1.20.2 / OTP 29 and the matching
repository's compiled test ebin directory:

```sh
mise exec -- mix run qa/function_selection/probe.exs ecto /path/to/ecto/_build/test/lib/ecto/ebin qa/function_selection/ecto.json
mise exec -- mix run qa/function_selection/probe.exs livebook /path/to/livebook/_build/test/lib/livebook/ebin qa/function_selection/livebook.json
```

Both checkouts were clean before these read-only probes. Results are retained in
`ecto.json` and `livebook.json`. Every selected target list and every selected
counter matched the full-scope result. All runs completed and restored the
module MD5; no check worker remained alive. Typespec and structural checks each
counted eight calls. Ecto retained three unknown typespec targets. Both modules
retained two unknown compiler alternatives and zero compiler calls in both
scopes. Do not interpret these compiler results as successful instrumentation.
The package acceptance tests separately exercise actual inferred compiler
instrumentation, selection of a function beyond the default ten-function cap,
child calls, and three restoration cycles.

The acceptance suite also exercises selection before remote-type loading,
module loading, structural classifier construction, ordered return claims,
exact default arities, custom-check rejection, empty diagnostics, and default
4096-message queue exhaustion. Before implementation, 14 scoped tests failed
at the unsupported `:only` option while the full-scope characterization passed.
After implementation all 15 acceptance tests and all 207 package tests passed.
