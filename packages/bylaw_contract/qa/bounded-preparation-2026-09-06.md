# Bounded structural preparation investigation

Beads: `bylaw-contract-investigate-bounded-structural-preparation`.

The question is whether preparing smaller groups of modules reduces structural
startup memory enough to justify additional compilation and lifecycle costs.
The baseline already includes the retained-clause-body improvement from PR 302:
Bylaw `7e01990768b1fb4d6991a56124c5e6146215434d`. This investigation changes
QA tooling and tests; the production library is unchanged.

Decision: retain the reproducible QA experiment and reject production batching.
The combined batching/GC candidate lowers memory, but consumes more of the fixed
shadow pool and does not provide a consistent startup speedup. A default change
would make previously viable observers fail under slot pressure. The already
merged body-retention improvement remains the production memory optimization.

## Candidate and comparison

`bounded-preparation.exs` composes the existing FunctionClauses check in groups
of 16 or 64 selected, unique, sorted modules. It explicitly collects garbage
between groups, includes that work in startup time, and keeps every prepared
shadow active throughout the same observation window. It combines the original
plans and routes events with their original caller identity. Partial startup
errors unwind shadows already owned by that candidate.

The candidate combines smaller compilation units with explicit garbage
collection, including after its final unit. An aggregate-plus-GC-only external
control was not run, so these measurements do not isolate the contribution of
each mechanism. They evaluate the complete proposed candidate and its costs.

This bounds modules per compilation, not clauses, functions or bytes. One very
large module remains a large unit. The candidate consumes one existing shadow
slot per group instead of one per observer. It does not add atoms or expand the
32-slot pool. No batching option or new configuration is added to the library.

The earlier per-function closure experiment in
`structural-startup-2026-09-05.md` was rejected for its time/memory tradeoff.
This experiment therefore compares whole-module units with the existing joint
head/guard classifier, rather than repeating that representation change.

## Measurement contract and reproduction

Runtime: Elixir 1.20.2, OTP 29.0.3, ARM64 macOS, 14 schedulers. All variants use
the same library BEAM files. Manifests retain library, QA, fixture and BEAM hashes
and reject changes during a matrix. External checkouts remain clean at Ecto
`11784f821a1bb0eedeee59583e311d836cb39ee1` and Livebook
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`. Their source, dependencies, tests and
timeouts are not edited. The previously assessed Realtime and LiveView pins
have incompatible native toolchains; they are not upgraded for this comparison.

Framework-free persisted fixtures vary one axis at a time: 4/16/64 modules,
1/4/16 functions per module, 3/6/12 clauses per function and 0/2/8 additional
guard terms. Function bodies remain small tuples; default arities and overlapping
heads/guards remain observable. All nine configurations are generated and
independently checked before measurement.

Each fresh direct-probe VM performs two complete start/workload/stop windows,
labelled `first` and `repeated`. These are within-VM first/repeated calls, not
cold filesystem/cache claims. Fixtures execute five values per function and
check every arity, clause selection, head match, guard pass and rejection against
an independent oracle. Direct Ecto/Livebook preparation windows execute no
application workload; their exact zero-event coverage is a preparation control,
not evidence of full-suite observation.

The native matrix runs normal Mix requiring and ExUnit execution with both
default checks, seed 922331, max_cases 4 and max_requires 14. It covers full Ecto,
the isolated Livebook NodeManager test at line 8, and full Livebook. It captures
the original test identities, required paths, failures, compiler options,
overlapping timing boundaries and complete/incomplete coverage. Only the QA
candidate's check-module identity is normalized for coverage comparison.

Three trials rotate aggregate/16/64 order. Every command has a 120-second
deadline and 1536 MiB sampled process-tree RSS and physical-footprint cutoffs.
One `ps` snapshot identifies the owned process tree roughly every 100 ms;
macOS `proc_pid_rusage` supplies successfully sampled physical footprints.
These are sampled bounds, not hard memory guarantees; RSS may count shared
pages twice and both samplers may miss short peaks. Native `/usr/bin/time -l`
wall/CPU/max-RSS counters are retained separately. Whole-command peaks include
bootstrap, both direct cycles, reporting and cleanup; they cannot be assigned
to one direct cycle. Python elapsed time includes polling/reaping overhead.

Separate diagnostic VMs wrap preparation/activation/cleanup phases and enable
Erlang compiler pass timing. Their source compilation, queue sampling and
compiler logging are excluded from the unprofiled matrix. Spans are nested and
inclusive; summing them would double count. Runtime-map construction is the
check-init residual after its direct load/start-shadow children and also includes
callback bookkeeping. BEAM total/process/binary/code/ETS snapshots are point
measurements, not allocation totals or guaranteed peaks.

Run from `packages/bylaw_contract`, using a new output directory each time:

```sh
MIX_ENV=test mise exec -- mix compile
mise exec -- elixir qa/bounded-preparation-fixtures.exs /tmp/bounded-fixtures
mise exec -- python3 qa/run-bounded-preparation.py prepare \
  _build/test/lib/bylaw_contract/ebin /tmp/bounded-fixtures /tmp/bounded-prepare \
  --ecto "$ECTO" --livebook "$LIVEBOOK" --trials 3
mise exec -- python3 qa/run-bounded-preparation.py native \
  _build/test/lib/bylaw_contract/ebin /tmp/bounded-fixtures /tmp/bounded-native \
  --ecto "$ECTO" --livebook "$LIVEBOOK" --trials 3
mise exec -- python3 qa/run-bounded-preparation.py diagnostic \
  _build/test/lib/bylaw_contract/ebin /tmp/bounded-fixtures /tmp/bounded-diagnostic \
  --ecto "$ECTO" --livebook "$LIVEBOOK" --trials 1
```

## Preparation results

All 99 final preparation commands pass, yielding 198 complete windows. Each
case has exactly one full normalized coverage hash and one report hash across
all variants, trials and both windows. Source MD5s match and cleanup succeeds.

Three-trial medians below include startup compilation and activation. Sampled
memory peaks cover the entire two-window command, not just the startup interval.

| Project / modules per unit | First start, s [range] | Repeated start, s | Peak tree RSS, MiB | Peak footprint, MiB | Active slots |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ecto aggregate | 6.016 [5.902, 6.179] | 5.909 | 534.9 | 545.5 | 1 |
| Ecto 16 | 6.900 [6.281, 7.601] | 6.519 | 281.9 | 270.9 | 7 |
| Ecto 64 | 5.967 [5.960, 6.283] | 6.083 | 485.8 | 477.6 | 2 |
| Livebook aggregate | 7.398 [7.136, 7.533] | 7.212 | 773.8 | 758.8 | 1 |
| Livebook 16 | 7.390 [7.119, 7.517] | 7.169 | 289.0 | 271.3 | 23 |
| Livebook 64 | 7.350 [7.079, 7.401] | 7.090 | 365.6 | 355.7 | 6 |

The memory reduction repeats on these two projects. Size 16 lowers median
sampled RSS by about 47% in Ecto and 63% in Livebook, while Ecto's first startup
becomes about 15% slower. Livebook's startup ranges overlap closely. Size 64
trades a smaller memory reduction for fewer slots, without a consistent startup
speedup across first/repeated windows. Three samples are descriptive ranges,
not confidence intervals or general performance guarantees.

| Fixture (modules / functions / clauses / extra guards) | Aggregate first start, ms | Size 16, ms | Size 64, ms |
| --- | ---: | ---: | ---: |
| 4 / 1 / 3 / 0 | 30 | 31 | 35 |
| 16 / 1 / 3 / 0 | 65 | 72 | 70 |
| 64 / 1 / 3 / 0 | 199 | 228 | 207 |
| 4 / 4 / 3 / 0 | 66 | 66 | 66 |
| 4 / 16 / 3 / 0 | 276 | 268 | 266 |
| 4 / 1 / 6 / 0 | 40 | 41 | 40 |
| 4 / 1 / 12 / 0 | 73 | 72 | 72 |
| 4 / 1 / 3 / 2 | 31 | 32 | 30 |
| 4 / 1 / 3 / 8 | 44 | 41 | 41 |

Only the 64-module fixture actually splits at size 16. Its median sampled RSS
falls from 135.4 to 106.4 MiB, using four slots, while first startup rises from
199 to 228 ms. The function/clause/guard axes remain a single compilation unit;
their small timing differences do not establish a batching benefit.

## Native suite results

All 27 native commands and their 27 offline decoders pass. Every variant/trial
has the same native inventory and required-file list for its scenario: 1,591
passing Ecto tests; one passing isolated Livebook test; or 1,511 passing full
Livebook tests plus 185 existing exclusions. All nine isolated observations are
complete and have identical full normalized coverage and rendered reports.
All 18 full-suite observations are explicitly incomplete at the unchanged
4096-message trace-queue guard. Their wall times cannot establish faster
complete-suite observation.

| Native scenario / unit size | Wall median, s [range] | Init median, s | Peak tree RSS median, MiB | Peak footprint median, MiB | Stop median, ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ecto full / aggregate | 8.43 [8.38, 8.47] | 7.356 | 646.0 | 608.5 | 6.6 |
| Ecto full / 16 | 8.65 [8.63, 8.78] | 7.555 | 523.3 | 505.7 | 17.4 |
| Ecto full / 64 | 8.42 [8.03, 9.04] | 7.339 | 623.1 | 606.1 | 8.6 |
| Livebook isolated / aggregate | 10.27 [10.22, 10.41] | 8.025 | 794.9 | 777.4 | 25.5 |
| Livebook isolated / 16 | 10.25 [10.23, 10.50] | 7.990 | 318.6 | 299.8 | 84.6 |
| Livebook isolated / 64 | 10.12 [10.10, 10.18] | 7.943 | 406.8 | 387.7 | 40.4 |
| Livebook full / aggregate | 17.70 [16.96, 18.10] | 9.678 | 912.5 | 887.4 | 15.3 |
| Livebook full / 16 | 17.20 [16.76, 18.86] | 9.252 | 568.0 | 532.7 | 81.0 |
| Livebook full / 64 | 17.06 [16.89, 17.19] | 9.415 | 592.4 | 543.9 | 31.1 |

The candidate's lower memory survives native loading/execution. It also adds
cleanup cost: isolated Livebook stop rises from 25.5 to 84.6 ms at size 16.
The small wall-time changes do not offset the demonstrated slot-capacity loss.
No measured command crosses its deadline or sampled memory cutoffs.

Every native capture reports clean worker/shadow/session cleanup, zero fallback
stops and only the legacy trace session remaining. Isolated Livebook retains
`compiler_options_restored: false`, as in the earlier disabled control: its
NodeManager lifecycle changes `ignore_module_conflict`. This is preserved rather
than overwritten or labelled as a new observer leak; see the control discussion
in `preparation-overlap-2026-09-06.md`.

## Phase attribution

All nine separately instrumented commands pass, yielding 18 additional complete
windows with the same per-case coverage/report hashes. The following values are
the mean of the two windows in one diagnostic VM, in seconds. Unit-local spans
are summed across units before dividing by two. These are descriptive phase
measurements, not independent paired speedup trials.

| Case / unit size | Metadata load | Forms | Compilation | Check-state residual | Activation | Shadow cleanup |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 64-module fixture / aggregate | 0.014 | 0.001 | 0.141 | 0.001 | 0.035 | 0.002 |
| 64-module fixture / 16 | 0.015 | 0.002 | 0.152 | 0.001 | 0.032 | 0.007 |
| 64-module fixture / 64 | 0.013 | 0.001 | 0.140 | 0.001 | 0.032 | 0.002 |
| Ecto / aggregate | 0.117 | 0.005 | 5.383 | 0.004 | 0.351 | 0.002 |
| Ecto / 16 | 0.118 | 0.004 | 5.671 | 0.002 | 0.346 | 0.013 |
| Ecto / 64 | 0.115 | 0.004 | 5.430 | 0.003 | 0.348 | 0.004 |
| Livebook / aggregate | 0.482 | 0.013 | 5.494 | 0.007 | 1.198 | 0.002 |
| Livebook / 16 | 0.475 | 0.006 | 5.371 | 0.005 | 1.227 | 0.046 |
| Livebook / 64 | 0.505 | 0.005 | 5.491 | 0.005 | 1.136 | 0.012 |

Compilation dominates structural startup in these external controls. The check
state residual subtracts each original FunctionClauses init's load and
start-shadow children; it includes callback bookkeeping. Between-unit GC and
composition sit outside those original callbacks and remain included in total
startup. The table is not a partition of the entire command, and other nested
spans retained in the artifact must not be added to it as independent costs.

Compiler-pass extraction includes only generated-shadow compilation blocks,
excluding the diagnostic tool's own source compilation. Mean `beam_ssa_opt`
time is 3.438/3.647/3.473 seconds for Ecto aggregate/16/64 and
3.113/3.088/3.146 seconds for Livebook. The full pass lists, rounded by the
compiler, remain in the artifact. Smaller units reduce peak memory here without
eliminating the expensive compiler work. Livebook activation remains roughly
1.1–1.2 seconds and is investigated separately in
`bylaw-contract-investigate-trace-activation-cost`.

## Correctness, capacity and review

Four acceptance tests first ran as an empty inventory, then all four failed
with the QA helper absent, then passed with it present. They cover exact
targets/counters/source metadata/reports, overlapping observers and distinct
caller identities, partial initialization under slot pressure, and repeated
start/stop cleanup. The capacity test fills the pool to 31 occupied slots: the
aggregate check can still initialize; a two-unit candidate fails and releases its first unit
without disturbing the reserved shadows.

The first repository-wide QA run exposed three incorrect global-pool assertions
in the new tests. An earlier worker-kill test leaves a shadow through the already
deferred `bylaw-contract-release-shadow-after-worker-kill` issue. The new tests
now snapshot and preserve existing shadows and assert their own allocation and
cleanup. Each test deliberately starts with an occupied shadow, so the focused
four-test suite verifies that ownership boundary independently of test order.
The original failed QA log is retained; the pre-existing leak is not fixed or
hidden by purging another owner's module.

An independent review tested 23 persisted modules, 84 clauses, 52 arities and
20 combinations of unit size and selection, with 1,073 events per combination.
Plans and full coverage matched exactly, source module MD5s were preserved,
and cleanup released all shadows. Empty, absent, duplicate/reversed and partial
module/MFA selections were included.

The reviewer also reproduced a pre-existing concurrent shadow-allocation bug
on the unchanged aggregate check: ten barrier-start trials out of ten shared
a shadow between independent observers; the candidate reproduced it too.
One observer can purge code still used by its peer. The global lock uses a
constant requester identity, and an isolated lock test confirms overlapping
entry. Erlang's [global lock documentation](https://www.erlang.org/doc/apps/kernel/global.html#set_lock/3)
distinguishes resource and requester identities and allows shared ownership
for the same requester. The issue is recorded as deferred P1
`bylaw-contract-isolate-concurrent-shadow-allocation`; this investigation does
not activate or fix it. Serial performance data cannot prove concurrent-start
safety. Ordinary overlapping-observer tests do not replace the barrier test.

## Retained unsuccessful attempts

The first formal preparation pass launched 99 commands: 81 fixture commands
passed and 18 external commands failed before `Contract.start`. Mix initialization
removed the standalone Bylaw `-pa` entry from the direct probe's path. The fix
explicitly prepends the caller-supplied ebin after Mix setup. The entire corrected
matrix uses a fresh `final/` directory; the original manifest, source and failed
logs remain intact. Native and diagnostic stages of the first matrix were never
launched. Four corrected external bootstrap controls then passed all eight
windows with exact coverage and report hashes.

The initial native smoke decoder mistakenly hashed the whole capture envelope,
including timings, through nested `update_in`. An independent correct-behavior
test failed against the archived decoder. Updating only the coverage map fixed
the same test for all three variants without changing or rerunning the native
captures. Original erroneous smoke fingerprints remain labelled as invalid;
final captures use the corrected decoder. These harness failures are not
performance results and are not silently discarded.

Raw logs, captures, source snapshots, manifests and review evidence are under
`/tmp/bylaw-bounded-preparation-20260906`. The compact results artifact retains
all final rows and initial-attempt outcomes, including nonzero commands.

Final independent review verifies all 135 main commands, 27 raw native captures,
2,769 summary statistics and 92 generated-shadow compiler-pass blocks, with no
remaining candidate-specific critical findings. It also runs the actual four
revised acceptance tests with an unrelated executable classifier held throughout:
its MD5 and caller-sensitive behavior remain intact, and all new shadows are
released. Repository-wide `scripts/qa.sh --seed 714795` passes, including all
974 UI tests. The seed reproduces the ordering of the retained initial QA failure.
