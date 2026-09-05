# Compiler function cap — 2026-09-05

Bead: `bylaw-contract-investigate-instrumentation-cap`.
Baseline: `25e0e8a6393865cb9b920df3bd203eb984b6d938`.
No production behavior or cap changes are included.

## Recommendation and semantics

Keep the default `max_functions: 10`. The synthetic fixture proves that a called
function can fall outside deterministic selection while selected functions stay
uncalled. Neither external project reached the cap in these measurements, so
raising it did not improve coverage. Existing explicit options and programmatic
warnings suffice for these cases. No new default, application-specific priority,
selection heuristic, public API or generic defect is justified by this evidence.

The check removes earlier checks' claims, retains authored alternatives, filters
individual alternatives by `inferable?`, groups them by MFA, sorts MFAs using
Erlang term order, and takes the first N groups. Instrumentation can then reject
a selected group. Selection precedes calls; declaration order and future call
frequency do not prioritize functions. Generated definitions consume no slots.

Cap omissions, unsupported inference, unknown authorship and failed
instrumentation are initially unknown. Successfully instrumented functions with
no calls become unknown at collection. Only assessable alternatives can be
missed. A group's total and inferable alternative counts can differ: use the
latter for cap selection.

Current public controls are an explicit module list and check options:

```elixir
Bylaw.Contract.start([MyApp.Accounts],
  checks: [{Bylaw.Contract.Check.ElixirCompiler, max_functions: 12}]
)
```

The formatter accepts the same check specification in `:bylaw_contract` options.
Scope is modules, not individual MFAs. No cap environment variable exists.
Although the API accepts `:infinity`, these experiments used only finite limits.

## Synthetic acceptance

Three named empty tests ran before bodies were implemented. The first fixture
run failed because in-memory compilation had not enabled inferred signatures;
correcting that fixture option made all three pass against unchanged production
code. No failing production regression or runtime fix is claimed.

The fixture varies 3, 10 and 14 authored functions, reverses declaration order,
and adds a lexically earlier generated function. Each authored function has two
independently known return alternatives. With 14 functions, call `f01`, `f11`,
`f12` and `f14` once each on their first alternative:

| Cap | Selected functions | Called and assessable | Observed alternatives | Missed alternatives | Unknown alternatives |
| --- | ---: | --- | ---: | ---: | ---: |
| 10 | 10 | f01 | 1 | 1 | 26 |
| 12 | 12 | f01, f11, f12 | 3 | 3 | 22 |

Before calls, all 28 alternatives are unknown at collection; only the 8
cap-omitted alternatives are initially unknown at cap 10. Tests verify exact
selection, counters, warnings, generated-definition exclusion and unknown sets.

## Approved external QA

Runtime: Elixir 1.20.2 / OTP 29.0.3. Seed: 922331; `max_cases: 28`.
Both tracked checkouts and lockfiles remained clean.

- Ecto `11784f821a1bb0eedeee59583e311d836cb39ee1`: data/query library with its
  default unit suite and no database service. Its `~> 1.14` Elixir requirement
  accepts this runtime; dependency resolution and compilation passed.
- Livebook `f18f2035bac89d6c08497f5f2d7e7c4f56e80716`: application with live
  processes and runtime sessions; upstream exclusions were unchanged.

Runs were sequential: Ecto 10, Ecto 20, Livebook 20, Livebook 10. The diagnostic
formatter invokes the actual compiler check with no earlier claims. This
isolates compiler selection; it does not measure the default checks together or
resolve the separate bounded trace-throughput issue.

| Project/cap | Tests passed | Eligible MFAs / alternatives | Chosen MFAs | Instrumented MFAs / alternatives | Cap omissions | Called instrumented MFAs | Assessable / hit / missed alternatives | Unknown alternatives |
| --- | ---: | --- | ---: | --- | ---: | ---: | --- | ---: |
| Ecto 10 | 1591 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 / 0 / 0 | 131 |
| Ecto 20 | 1591 | 0 / 0 | 0 | 0 / 0 | 0 | 0 | 0 / 0 / 0 | 131 |
| Livebook 20 | 1511 | 9 / 18 | 9 | 5 / 11 | 0 | 2 | 5 / 4 / 1 | 724 |
| Livebook 10 | 1511 | 9 / 18 | 9 | 5 / 11 | 0 | 2 | 5 / 4 / 1 | 747 |

Livebook excluded 185 tests in each run. All four suites exited successfully
and wrote terminal captures. Ecto's 131 alternatives were non-inferable: 101
belonged to non-finite return groups; the remaining 30 still lacked supported
inference. Zero cap omissions does not mean complete compiler coverage.

Four Livebook MFAs failed source instrumentation, with warnings retained:
`Livebook.Notebook.Cell.type/1`,
`Livebook.Runtime.Evaluator.ObjectTracker.handle_call/3`,
`LivebookWeb.AppAuthHook.on_mount/4` and
`LivebookWeb.SessionLive.send_output_update/4`. Native counters recorded calls
to all four despite their lack of assessable compiler coverage. Successfully
instrumented and called MFAs were `Livebook.NotebookManager.handle_info/2` and
`Livebook.Text.Delta.Operation.split_at/2`; three other instrumented MFAs stayed
uncalled. Exact lists, native counts, statuses, warnings and overlapping shape
flags are retained in `compiler-cap-results.json`.

Native call-count profiling measures all eligible MFAs without per-call message
payloads. A separate three-function smoke fixture verified selected calls (2),
an omitted function (3), and an uncalled function (0). In every external capture,
native counts for instrumented MFAs exactly equal Bylaw's compiler-call counts.
Native counts do not identify return branches or make unsupported inference
assessable.

## Costs and limitations

| Project/cap | Initialization (s) | Suite interval (s) | Process wall time (s) | Maximum RSS (bytes) |
| --- | ---: | ---: | ---: | ---: |
| Ecto 10 | 1.824 | 2.397 | 4.87 | 598228992 |
| Ecto 20 | 2.192 | 2.270 | 5.27 | 601210880 |
| Livebook 20 | 6.593 | 9.390 | 17.43 | 568999936 |
| Livebook 10 | 2.658 | 9.221 | 12.86 | 554778624 |

These single samples are not causal cap-overhead estimates. The cap did not
bind; compiler inspection timeouts and VM state differed. Livebook had 14
unsupported modules at cap 20 and 9 at cap 10. Ecto had 4 and 5 respectively,
including a safe-decoding rejection only at cap 10. These differences are
preserved; unknown totals cannot be compared as a cap effect. Raw BEAM memory
samples are in JSON, but GC makes their subtraction unsuitable as a retained
memory estimate. Native profiling adds overhead in both modes. These projects
do not establish a hard memory bound or general compiler compatibility.

## Reproduction

Run `mise exec -- mix test test/compiler_cap_acceptance_test.exs` in this package.
From an already compiled eligible approved checkout, export the actual paths:

```sh
export BYLAW_CAP_EBIN=/absolute/bylaw/package/_build/test/lib/bylaw_contract/ebin
BYLAW_CAP_APP=ecto BYLAW_CAP=10 BYLAW_CAP_OUTPUT=/fresh/capture.etf \
elixir -pa "$BYLAW_CAP_EBIN" -r /absolute/bylaw/package/qa/compiler-cap-capture.exs \
  -S mix test --seed 922331 --max-cases 28 \
  --formatter ExUnit.CLIFormatter --formatter CompilerCapCapture
```

Repeat at 20 and for Livebook. The diagnostic restores Bylaw's path during
formatter initialization after Mix adjusts paths. Run
`elixir qa/compiler-cap-results.exs CAPTURE...` to validate trusted local
captures and generate JSON. It checks terminal tests, known authorship, native
versus compiler counts, and alternative denominator identities.

Recorded captures precede the diagnostic's explicit claims filter and
selected-ID field. The verifier confirms no unknown-authorship warnings in
those runs, making eligibility equivalent. The maintained capture was rechecked
with the exact-count smoke fixture after those additions. Raw logs, captures,
runner and smoke scripts remain in `/tmp/bylaw-compiler-cap`.
