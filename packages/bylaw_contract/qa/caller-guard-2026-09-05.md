# Preserve traced caller identity in structural guards

Bead: `bylaw-contract-preserve-caller-guard-context`.
Baseline: `1fbc94900dab76fc446ae594a117175f3c5e8c61` (same library source as measured commit `0e470487f121c9ed20518cd80c34b90183faab19`).
Primary runtime: Elixir 1.20.2 / OTP 29.0.3.

## Reproduced error and fix

For `def who(pid) when pid == self(), do: :caller` followed by a fallback, `who(self())` returned `:caller` while complete structural coverage reported guard rejection and fallback selection. Passing the consumer PID produced the inverse error. The worker discarded the trace event's producer PID, and the shadow evaluated `self()` in the consumer.

TraceWorker now passes producer identity to checks that implement the optional `observe(event, caller, state)` callback. Existing checks continue receiving the same event tuples through `observe/2`; call and return callbacks still execute in the owning worker. Structural classification receives the original producer PID as a separate shadow argument, replacing guard `self()` calls with that variable for both selection and every clause outcome.

The injected variable is chosen outside the source patterns' and guards' variable set. Its compiler-only atom namespace is reused across observations and grows only when source variables collide with earlier names. The single `UnsafeToAtom` lint exception is limited to that generator; arbitrary runtime strings are not converted. A direct abstract-code test forces the initial name to collide and verifies correct head matches, rejections and selection.

## Verification

Four named empty acceptance tests were run before implementation. After adding bodies, all four failed on the baseline with exact counter mismatches: true caller, consumer identity as argument, interleaved child callers, and nested/alternative guards. All pass after the fix.

Two callback tests were separately inventoried: the original worker passes the legacy event-tuple test and fails producer-context delivery; the updated worker passes both. The variable-collision test passes. The complete package suite passes all 150 tests, and strict Credo passes. Logs are retained in `/tmp/bylaw-caller-guard`, including `acceptance-baseline.log`, `callback-baseline.log`, `hygiene-candidate.log`, `package-tests-final.log` and `credo-fixed.log`.

## Approved repository QA

Only approved Livebook (`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`) and synthetic fixtures were used. The checkout was not edited. Both sides used seed 922331, max_cases 28, the existing exclusions and all three contract checks.

The full candidate suite passed 1,511 tests with 185 excluded. The baseline suffered the previously observed runtime-connection setup timeout, invalidating 108 tests (1,403 passed). Both full-suite observations exceeded the unchanged 4096-event budget and explicitly reported incomplete coverage. This fix does not resolve the separately tracked full-suite throughput issue.

An isolated NodeManager test passed on both baseline and candidate with complete observations. This provides compatibility evidence, not a full-suite completeness or performance claim. `caller-guard-observation-results.json` retains commands, terminal states and measurements; raw captures and logs remain in `/tmp/bylaw-caller-guard`.

All 26 structural and callback tests also pass on Elixir 1.19.5 / OTP 28.5.0.4 in a separate build directory. Existing eliminated-function/compiler-inference warnings remain in `otp28-tests.log`. Repository-wide `scripts/qa.sh` passed; its log is `/tmp/bylaw-caller-guard/root-qa.log`.
