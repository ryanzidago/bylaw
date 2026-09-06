# Nonempty lists containing false and nil

Issue: `bylaw-contract-match-falsey-nonempty-lists`.
Baseline: `d3c535eb` on Elixir 1.20.2 / OTP 29.0.3.

`TypeMatcher` used `Enum.any?/1` to check nonemptiness, rejecting `[false]`,
`[nil]` and `[false, nil]` even when all elements matched. The fix uses
`not Enum.empty?/1` after the existing proper-list guard. Element matching and
its `:no_match` / `:unknown` precedence remain unchanged.

Nine named empty acceptance tests ran before their bodies were added. The final
bodies produced six expected failures on unchanged production code: three term
examples, false-only boolean lists, unknown element types and observed return
hits (zero instead of three). Empty/nonlist rejection, improper tails and
no-match precedence already passed. All nine pass with the fix, alongside five
existing matcher and improper-list tests. The runtime fixture checks unchanged
caller values, exact singleton/multiple input counts, exact return hits and an
unobserved return alternative. It confirms complete observation for both
`nonempty_list(term())` and `nonempty_list(boolean())`.

`scripts/qa.sh` passed all package formatting, compilation, strict Credo, tests
and documentation gates, repository workflow checks, and 974 UI tests.
An independent subagent reviewed the production change and regression tests and
reported no critical findings.

## Approved external QA

All runs used the same candidate source/BEAM hashes, original tests and native
concurrency (`max_cases: 28`), seed 922331 and unchanged queue limit 4096.
Ecto is pinned at `11784f821a1bb0eedeee59583e311d836cb39ee1`; Livebook at
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`. Both checkouts remained clean.

| Run | Tests | Observation |
| --- | --- | --- |
| Ecto full suite, default checks | 1,591 passed | Incomplete: Typespec queue 4,322; FunctionClauses 4,108 |
| Livebook initial full suite, default checks | 1,510 passed, 1 failed, 185 excluded | Incomplete: Typespec 4,160; FunctionClauses 4,146 |
| Livebook full suite, disabled comparison | 1,511 passed, 185 excluded | Disabled |
| Livebook full suite, default-check comparison | 1,511 passed, 185 excluded | Incomplete: Typespec 4,123; FunctionClauses 4,581 |
| Livebook isolated NodeManager test, default checks | 1 passed | Complete |
| Livebook isolated Standalone disconnect test, default checks | 1 passed, 2 excluded by line selection | Complete |

The initial failure was `Livebook.Runtime.StandaloneTest`'s `Runtime.disconnect/1`
test at `standalone_test.exs:36`: its child runtime failed startup, with an earlier
`Livebook.Runtime.EPMD.start_link/0` undefined-function error. Evidence was added
to the existing deferred `bylaw-qa-livebook-epmd-startup-race` issue. The passing
comparison and isolated test establish non-reproduction in those runs, not a
cause for the original failure. No upstream source, timeout, exclusion or
concurrency setting was changed. Full-suite passing tests do not establish
complete contract observation.

`falsey-nonempty-list-results.json` retains every terminal outcome, commands,
pins, source/BEAM hashes and failure details. Raw logs and ETF captures are under
`/tmp/bylaw-falsey-20260906`; `acceptance-red.log` records the failing baseline,
and `root-qa.log` records the repository gate.

## Reproduction

From `packages/bylaw_contract`, run the focused tests:

```sh
mix test test/falsey_nonempty_list_acceptance_test.exs test/improper_list_acceptance_test.exs test/type_matcher_test.exs
```

Run `scripts/qa.sh` from the repository root. For external QA, use the existing
`qa/run-performance-phases.py` runner with the approved checkout paths and fresh
output directories, for example from the package:

```sh
python3 qa/run-performance-phases.py ecto /tmp/bylaw-compiler-cap/ecto /tmp/falsey-ecto-new --modes defaults --trials 1 --max-cases default
python3 qa/run-performance-phases.py livebook /tmp/bylaw-reasons.oRUJf0/livebook /tmp/falsey-livebook-new --modes disabled defaults --trials 1 --max-cases default
```

For focused runs add `--selection test/livebook/runtime/erl_dist/node_manager_test.exs`
or `--selection test/livebook/runtime/standalone_test.exs:36`, with separate
fresh output directories. These results make no claim for unselected projects
or incompatible Elixir/OTP versions.
