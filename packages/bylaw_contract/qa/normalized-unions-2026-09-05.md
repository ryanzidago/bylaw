# Normalized compiler return unions — 2026-09-05

Beads: `bylaw-contract-handle-normalized-return-unions`.
Baseline: `51354ab83b5c4a00c2dd038ca94a8d075ea4bee5`.
Runtime: Elixir 1.20.2 / OTP 29.0.3.

## Defect and fix

The compiler normalizes return unions. For example, `:ok | atom() | integer()`
becomes `atom() | integer()`, and `{:ok, :one} | {:ok, :two} | :error` becomes
`{:ok, :one | :two} | :error`. Looking up the original clause labels with
`Map.fetch!` then fails, rejecting the entire module, including independent
functions with exact and assessable inference rules.

The decoder now retains normalized alternatives while requiring a complete
exact label mapping before exposing a function's inference rules. If any clause
label cannot be mapped, the entire function stays unassessable. This avoids
partially mapping a function and reporting false misses after an unmapped clause
executes. Other functions in that module retain their existing inference rules.
This is deliberately not semantic subtype matching: normalized functions may
remain unassessable even where a future, separately validated mapping could
recover them. No public API or instrumentation limit changed.

Five acceptance tests were first inventoried as runnable empty tests. All five
implemented tests failed on the baseline and passed after the fix. They cover
absorbed literals, merged tuple fields, dynamic wrappers, independent-function
runtime observation, and no misses for an unmappable function after a real call.
The compiled fixture uses ordinary Elixir source, not rewritten checker chunks.

## Pinned Livebook inspection

Repository: https://github.com/livebook-dev/livebook
Revision: `f18f2035bac89d6c08497f5f2d7e7c4f56e80716`.
Checkout: `/tmp/bylaw-reasons.oRUJf0/livebook`, compiled in test environment with
the runtime above. Run from this package directory:

```sh
PRELOAD_MODULES=1 mise exec elixir@1.20.2-otp-29 erlang@29.0.3 -- \
  elixir qa/compiler-reasons.exs /tmp/bylaw-reasons.oRUJf0/livebook livebook
```

| Static measurement | Before | After |
| --- | ---: | ---: |
| Application modules | 355 | 355 |
| Supported modules | 246 | 276 |
| Descriptor decode failures | 30 | 0 |
| Safe-term decoding failures | 75 | 75 |
| Missing inferred signatures | 4 | 4 |
| Raw alternatives | 377 | 723 |
| Alternatives claimed by Typespec | 140 | 281 |
| Generated exclusions after decoding | 7 | 153 |
| Retained authored alternatives | 230 | 289 |
| Non-inferable authored alternatives | 220 | 277 |
| Inferable alternatives | 10 | 12 |
| Selected functions | 5 | 6 |
| Cap omissions | 0 | 0 |

The new `missing_exact_clause_mapping` diagnostic flag accounts for 45 retained
authored alternatives after the fix. The script now accepts functions with no
inference rules. Its unsupported-input flag inspects available rules only;
absence of rules is reported separately and is not proof that inputs are
supported. Flags overlap and must not be summed. These are static inventories,
not runtime hit counts. The safe-decoding issue remains separately tracked in
`bylaw-contract-investigate-safe-checker-decoding`.

## Validation

The complete package suite passed 89 tests. Strict Credo and repository-wide
`scripts/qa.sh` passed, including 974 UI tests. The QA script was explicitly
formatted because `qa/` is outside the default formatter inputs.

The full pinned Livebook suite was also exercised. Bylaw's compiled package
`ebin` directory was added with `elixir -pa ... -S mix test`; only the disposable
checkout's `ExUnit.start/1` options were temporarily changed to select checks.
`BYLAW_CONTRACT_APPS=livebook BYLAW_CONTRACT_REPORT=summary` selected the target
and output mode. External dependencies and lockfiles were unchanged.

- All three checks, seed 109867: 1510/1511 passed, 185 excluded, 15.5 seconds.
  `Livebook.Apps.DeployerTest` at `test/livebook/apps/deployer_test.exs:63`
  timed out waiting for a deployment result after 1500 ms. No durable Bylaw
  summary was emitted before VM exit, so this run supplies no runtime coverage
  counters.
- Without Bylaw, same seed: 1510/1511 passed, 185 excluded, 9.9 seconds.
  A different lifecycle test, `Livebook.Runtime.StandaloneTest` at
  `test/livebook/runtime/standalone_test.exs:36`, failed. This baseline does not
  prove the instrumented deployment timeout was unrelated to Bylaw.

- Compiler check only, same seed: all 1511 passed, 185 excluded, 10.6 seconds.
  This run also exited without a durable Bylaw summary. Check configuration and
  suite success alone are not evidence of specific runtime coverage totals.

The disposable helper was restored, and `git status --short` was empty.
A fresh-VM controlled call provided explicit runtime evidence: after compiling
Bylaw in memory and adding Livebook's compiled dependency paths (as the static
script does), the following completed successfully:

```elixir
module = Livebook.Text.Delta.Operation
{:ok, tracer} = Bylaw.Contract.start([module],
  checks: [Bylaw.Contract.Check.ElixirCompiler])
module.split_at({:retain, 4}, 2) # {{:retain, 2}, {:retain, 2}}
coverage = Bylaw.Contract.stop(tracer)
# coverage.compiler_calls == %{{module, :split_at, 2} => 1}
```

The retain-pair alternative had hit value 1; the insert/delete pair alternatives
had no hit and were assessable. Both `from_compressed/1` alternatives remained
unknown because their normalized labels have no exact clause mapping. This
checks observation and conservative exclusion together on real upstream code.

The differing timing failures are a limitation of this external suite run,
not a clean-suite claim. Instrumentation timing and formatter completion are
tracked by `bylaw-contract-investigate-qa-overhead`.
