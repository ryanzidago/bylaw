# Bylaw.Contract external QA — 2026-09-05

This is the historical initial-run evidence log. Clones were disposable and created
under `/tmp/bylaw-contract-qa.Ef0vbA`; no external repository was committed to.
The timing failures below did not have controlled disabled baselines and must
not be attributed to external causes solely because no Bylaw exception appeared.
See [the paired overhead investigation](qa-overhead-2026-09-05.md) for subsequent
evidence, runtime differences, incomplete observations, and remaining uncertainty.

## Toolchain

The repository `mise.toml` supplied Erlang/OTP 29.0.3 and Elixir 1.20.2-otp-29.
The observed runtime was Erlang/OTP 29 (erts-17.0.3), Elixir 1.20.2 compiled
with OTP 29. No `.tool-versions` file was added.

## Pinned commits

| Repository | Commit | Status |
| --- | --- | --- |
| Plausible | `543b30185c104ce17900d03c95d95429180acc0b` | run complete below; 4 external setup failures |
| Changelog | `3e46efd3773e9c375633d49d9353608f294da15d` | run complete below |
| Realtime | `21ce9acb5a171b07d7494a80fe0a3f2d008f5710` | run complete below; 1 peer-start failure, attribution unresolved |
| Phoenix | `1e6183e9ebab9994cf6e43d3af445f32664cc10c` | run complete below |
| Phoenix LiveView | `8015b9c09a5606f5f3e7204a64ecf9cc28c5b683` | terminal summary missing; async/LiveReload timing failures observed, attribution unresolved |
| FLAME | `2b124f3ffdede8c1f125ce36b237bef1c50940a3` | run complete below |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | run complete below |
| Ecto | `11784f821a1bb0eedeee59583e311d836cb39ee1` | run complete below |
| Vutuv | `fca6484d08a7e5dab1a2a405e5de358eee3d512a` | run complete below |

## FLAME

The disposable clone temporarily used the local path dependency and enabled
`Typespec`, `FunctionClauses`, and `ElixirCompiler` through the ExUnit formatter.
Command:

```sh
mise exec -- mix deps.get
BYLAW_CONTRACT_REPORT=summary mise exec -- mix test \
  --formatter ExUnit.CLIFormatter \
  --formatter Bylaw.Contract.ExUnitFormatter
```

Result: **62 passed**, 16.7 seconds. Summary:

```text
functions=7 arguments=14 calls=22 input_classes=14 supported_input_classes=14
observed_input_classes=2 missed_input_classes=12 unsupported_input_classes=0
return_groups=2 return_events=11 return_alternatives=4
observed_return_alternatives=1 missed_return_alternatives=3
compiler_return_groups=3 compiler_return_alternatives=6
compiler_unsupported=3 compiler_warnings=3 clauses=192 clauses_selected=171
clauses_head_matched=173 guarded_clauses=36 guards_passed=35 guards_rejected=6
callable_arities=174 arity_calls=4723 structural_unsupported=0 warnings=0
```

The suite also emitted repeated FLAME `Terminator.clean_up_paths/1`
`FunctionClauseError` logs at the pinned commit. This is recorded as an
external-suite failure signal; no Bylaw defect has been inferred from it.

## Plausible

The pinned clone used its native mise toolchain, PostgreSQL on disposable host
port 55434, ClickHouse on host port 8123, and the repository's documented
`npm run deploy --prefix tracker` asset build. The final rerun completed in
97.9 seconds: **5,888/5,892 passed** (67/67 doctests, 5,821/5,825 tests), 67
excluded, 4 failures. The failures were MinIO availability and session-salt
state tests; the initial asset-related failures disappeared after the required
tracker build. Summary:

```text
functions=857 arguments=1603 calls=772977 input_classes=2702
supported_input_classes=2605 observed_input_classes=1247 missed_input_classes=1358
unsupported_input_classes=97 return_groups=290 return_events=421539
return_alternatives=644 supported_return_alternatives=579
observed_return_alternatives=318 missed_return_alternatives=261
unsupported_return_alternatives=65 compiler_return_groups=220 compiler_call_events=1753
compiler_return_alternatives=495 supported_compiler_return_alternatives=8
observed_compiler_return_alternatives=6 missed_compiler_return_alternatives=2
unsupported_compiler_return_alternatives=487 compiler_modules=738
compiler_unsupported=125 compiler_warnings=125 clauses=6243 clauses_selected=4945
clauses_head_matched=5014 guarded_clauses=382 guards_passed=344 guards_rejected=220
callable_arities=5017 arity_calls=8825302 structural_unsupported=0 warnings=0
```

## Ecto

The disposable clone temporarily used the local path dependency and enabled
the same three checks. Command:

```sh
mise exec -- mix deps.get
BYLAW_CONTRACT_REPORT=summary mise exec -- mix test \
  --formatter ExUnit.CLIFormatter \
  --formatter Bylaw.Contract.ExUnitFormatter
```

Result: **1,591 passed** (97 doctests, 1,494 tests), 0.6 seconds. Summary:

```text
functions=184 arguments=514 calls=79524 input_classes=1377
supported_input_classes=1034 observed_input_classes=643 missed_input_classes=391
unsupported_input_classes=343 return_groups=45 return_events=7353
return_alternatives=232 supported_return_alternatives=154
observed_return_alternatives=69 missed_return_alternatives=85
unsupported_return_alternatives=78 compiler_return_groups=7
compiler_return_alternatives=14 compiler_unsupported=22 compiler_warnings=22
clauses=2552 clauses_selected=1938 clauses_head_matched=2068
guarded_clauses=467 guards_passed=399 guards_rejected=286
callable_arities=1223 arity_calls=305775 structural_unsupported=0 warnings=0
```

The run emitted only the target suite's existing type warnings and completed
without test failures. Detailed candidate review remains pending; aggregate
counts alone are not evidence of actionable gaps.

## Phoenix

The pinned clone used its native mise toolchain and the local path dependency.
The complete default suite was run with all three checks enabled using the same
formatter command shown above. Result: **1,087 passed** (11 doctests, 1,076
tests), 33 excluded, 13.2 seconds. Summary:

```text
functions=103 arguments=210 calls=7400 input_classes=346
supported_input_classes=298 observed_input_classes=188 missed_input_classes=110
unsupported_input_classes=48 return_groups=20 return_events=2235
return_alternatives=44 observed_return_alternatives=35 missed_return_alternatives=9
compiler_return_groups=34 compiler_call_events=1572 compiler_return_alternatives=74
supported_compiler_return_alternatives=4 observed_compiler_return_alternatives=2
missed_compiler_return_alternatives=2 unsupported_compiler_return_alternatives=70
compiler_modules=92 compiler_unsupported=10 compiler_warnings=10 clauses=1409
clauses_selected=1127 clauses_head_matched=1171 guarded_clauses=185
guards_passed=164 guards_rejected=88 callable_arities=1067 arity_calls=165776
structural_unsupported=0 warnings=0
```

## Phoenix LiveView

The complete suite was rerun under the repository's native Elixir 1.18.3 /
OTP 27.3.3 mise toolchain with the local path dependency and all three checks.
No durable final formatter line was retained after the terminal session closed,
so a complete terminal result is unverified. Failures observed were timing-sensitive
tests, including `Phoenix.LiveView.StreamAsyncTest` at
`test/phoenix_live_view/integrations/stream_async_test.exs:224` and the earlier
`Phoenix.LiveView.LiveReloadTest` custom-reloader timeout. No Bylaw exception
or compiler-check failure was observed; this does not establish an external cause.

## Vutuv

The pinned clone used its native mise toolchain (Elixir 1.20.0 / OTP 28.5.0.1),
the local path dependency, PostgreSQL test services already configured by the
repository, and all three Bylaw.Contract checks. Command:

```sh
mise exec -- mix deps.get
BYLAW_CONTRACT_REPORT=summary mise exec -- mix test \
  --formatter ExUnit.CLIFormatter \
  --formatter Bylaw.Contract.ExUnitFormatter
```

Result: **10,167 passed** (4 doctests, 10,163 tests), 203.0 seconds. The suite
emitted deliberate application warnings/errors and Postgrex sandbox owner
disconnect logs but completed successfully. Summary:

```text
functions=149 arguments=275 calls=128149 input_classes=532
supported_input_classes=532 observed_input_classes=85 missed_input_classes=447
unsupported_input_classes=0 return_groups=72 return_events=47842
return_alternatives=174 supported_return_alternatives=174
observed_return_alternatives=30 missed_return_alternatives=144
unsupported_return_alternatives=0 compiler_return_groups=325 compiler_call_events=23
compiler_return_alternatives=848 supported_compiler_return_alternatives=1
observed_compiler_return_alternatives=1 missed_compiler_return_alternatives=0
unsupported_compiler_return_alternatives=847 compiler_modules=823
compiler_unsupported=217 compiler_warnings=217 clauses=15913
clauses_selected=13506 clauses_head_matched=14125 guarded_clauses=1382
guards_passed=1212 guards_rejected=601 callable_arities=11596
arity_calls=11141069 structural_unsupported=0 warnings=0
```

## Changelog

The pinned clone used its native mise toolchain (Elixir 1.18.3 / OTP 27.3.3),
the local path dependency, its configured PostgreSQL test service, and all
three Bylaw.Contract checks. Command:

```sh
mise exec -- mix deps.get
BYLAW_CONTRACT_REPORT=summary mise exec -- mix test \
  --formatter ExUnit.CLIFormatter \
  --formatter Bylaw.Contract.ExUnitFormatter
```

Result: **974 tests, 0 failures**, 33.7 seconds. Summary:

```text
functions=369 arguments=824 calls=165 input_classes=2098
supported_input_classes=2095 observed_input_classes=43 missed_input_classes=2052
unsupported_input_classes=3 return_groups=233 return_events=129
return_alternatives=602 supported_return_alternatives=602
observed_return_alternatives=19 missed_return_alternatives=583
unsupported_return_alternatives=0 compiler_return_groups=0
compiler_return_alternatives=0 compiler_modules=350 compiler_unsupported=350
compiler_warnings=350 clauses=2956 clauses_selected=1815
clauses_head_matched=1869 guarded_clauses=141 guards_passed=86
guards_rejected=75 callable_arities=3416 arity_calls=1714050
structural_unsupported=0 warnings=0
```

Compiler inference was unavailable for all 350 inspected modules in this
repository/toolchain combination; those are inference limitations, not
actionable missing tests.

## Livebook

The pinned clone used its native mise toolchain, the local path dependency, and
all three Bylaw.Contract checks. Command:

```sh
mise exec -- mix deps.get
BYLAW_CONTRACT_REPORT=summary mise exec -- mix test \
  --formatter ExUnit.CLIFormatter \
  --formatter Bylaw.Contract.ExUnitFormatter
```

Result: **1,510/1,511 passed** (87/87 doctests, 1,423/1,424 tests), 185
excluded, 1 failure, 6.9 seconds. The observed failure, with unresolved attribution, was
`Livebook.Runtime.ErlDist.NodeManagerTest`, `test terminates when the last
runtime server terminates`, which timed out waiting for
`{:runtime_connect_done, pid, {:ok, runtime}}`.

Summary:

```text
functions=784 arguments=1383 calls=446869 input_classes=2265
supported_input_classes=2113 observed_input_classes=1187 missed_input_classes=926
unsupported_input_classes=152 return_groups=297 return_events=84229
return_alternatives=683 supported_return_alternatives=651
observed_return_alternatives=294 missed_return_alternatives=357
unsupported_return_alternatives=32 compiler_return_groups=144
compiler_call_events=379 compiler_return_alternatives=309
supported_compiler_return_alternatives=5 observed_compiler_return_alternatives=3
missed_compiler_return_alternatives=2 unsupported_compiler_return_alternatives=304
compiler_modules=355 compiler_unsupported=51 compiler_warnings=51 clauses=5246
clauses_selected=3513 clauses_head_matched=3598 guarded_clauses=275
guards_passed=193 guards_rejected=160 callable_arities=3693
arity_calls=1238891 structural_unsupported=0 warnings=0
```

## Realtime

The pinned clone used its native mise toolchain. Its documented registry and
tenant PostgreSQL services were provisioned in disposable Docker projects on
host ports 55432 and 55433, migrated, seeded, and the suite was rerun. The
complete run took 616.6 seconds: **2,195/2,196 passed** (23 doctests, 2,173
tests), 6 excluded, 1 failure. The failure was `Realtime.GenRpcBadTcpTest`,
which timed out starting a peer and emitted SQL sandbox/peer lifecycle logs;
the missing disabled baseline leaves attribution unresolved.

Summary:

```text
functions=375 arguments=792 calls=273928 input_classes=1457
supported_input_classes=1432 observed_input_classes=470 missed_input_classes=962
unsupported_input_classes=25 boundaries=2 observed_boundaries=0 missed_boundaries=2
return_groups=144 return_events=95229 return_alternatives=336
supported_return_alternatives=326 observed_return_alternatives=146
missed_return_alternatives=180 unsupported_return_alternatives=10
compiler_return_groups=0 compiler_call_events=0 compiler_return_alternatives=0
compiler_modules=369 compiler_unsupported=369 compiler_warnings=369 clauses=2169
clauses_selected=1624 clauses_head_matched=1681 guarded_clauses=201 guards_passed=149
guards_rejected=86 callable_arities=1942 arity_calls=4780383
structural_unsupported=0 warnings=0
```

The initial missing-`supabase_admin` failure was resolved by using the
repository's Docker setup with isolated ports; no Bylaw defect was inferred.

## Local gate results

`packages/bylaw_contract`: **77 tests passed**. Strict Credo: **545 mods/funs,
no issues**. `git diff --check`: passed. The repository-wide `scripts/qa.sh`
initially exposed a concurrency-sensitive `bylaw_ui` browser harness failure
(20 concurrent Bun test files left contexts open). The QA command was made
deterministic with `bun test --max-concurrency=1`; the final gate passed with
**974 tests, 0 failures**, including formatting, build, typecheck, and browser
tests.

## Candidate review

No Beads issue has been created: no candidate has been confirmed as an
actionable Bylaw defect. Aggregate reports identify missed and unsupported
counts, but the remaining candidate-level review is explicitly limited to
MFA, inferred alternative, hit count, source location, and unsupported reason;
counts alone are not being classified as gaps.

Candidate counts and classifications are summarized in
`qa/candidate-summary.md`; the raw static snapshots were intentionally excluded
from the PR because they expanded the diff by roughly 396,000 generated lines.
The suite summaries remain authoritative for observed hits. Candidates were
reviewed as inference limitation, adequately tested, or not actionable; no
candidate met the threshold for a Beads issue.

## Cleanup note

Disposable Docker resources were removed. The clone root was moved to the
user's Trash using the recoverable cleanup command; no QA clone or service is
left running.
