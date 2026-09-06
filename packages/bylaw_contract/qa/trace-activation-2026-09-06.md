# Trace-pattern activation investigation

Beads: `bylaw-contract-investigate-trace-activation-cost`.

This study asks whether installing many selected function trace patterns does
avoidable work. The production baseline is Bylaw
`01bb23925bbf414c5132e65a9eac8e67ce710ebb`, including the retained-clause-body
memory improvement from PR 302 and the QA-only bounded-preparation study in
PR 303. No production source or public API changes in this investigation.

Decision: retain the reproducible measurement tools and reject an activation
optimization for now. Almost all measured pattern-configuration time is inside
individual `:trace.function/4` calls. Comparable set bookkeeping is small, and
bounded parallel installation does not show a useful gain. These observations
identify a cost; they do not establish a safe shortcut or a runtime defect.

## Measurement contract

Runtime: Elixir 1.20.2, OTP 29.0.3, ARM64 macOS, 14 schedulers. The controller
retains exact commands, source/BEAM hashes and runtime output, and rejects source
changes during each stage. All stages use the same compiled library. Separate
diagnostic VMs recompile only TraceWorker in memory with timing wrappers; they
restore the complete compiler-options map afterward. Ordinary measurements use
the original library BEAM.

The fixture has 128 persisted modules with 64 public identity functions each.
Every measured VM preloads all 8,192 functions before timing. The requested
prefix varies over 0, 64, 256, 1,024, 4,096 and 8,192 functions, with call-only,
return-only, both, or mixed interests. Mixed repeats call-only, return-only,
both. This varies selected scope while holding loaded fixture code constant;
smaller scopes are not same-work speedups.

Each fresh VM performs two complete start/workload/stop windows, labelled first
and repeated. These are within-VM calls, not cold-cache or fresh-build claims.
The direct QA check avoids typespec extraction and structural compilation so
activation can be measured independently. Before each start, a comparable
MapSet union/membership/checksum loop records bookkeeping time. It is a control,
not an exact subtraction of production overhead; its first call includes lazy
code loading. Repeated-call results better indicate the small warm loop cost.

The direct probe verifies every selected pattern and every unselected export,
including implicit exports, using `:trace.info`. It calls every selected
function once and checks the exact ordered call/return events and original
caller PID against an independent oracle. Groups of 64 calls use trace-delivery
and worker-state barriers to keep observations complete under the unchanged
4096-message guard. Workload time includes this pacing and copied worker states;
it is not native application throughput. Coverage hashing removes only caller
PID identity after asserting it. The custom check renders no report text, so
its identical empty-report hash carries no additional semantic evidence.
Native built-in-check reports are checked separately.

Whole-command `/usr/bin/time -l` wall/CPU/max-RSS counters remain separate from
Python controller elapsed time. Roughly every 100 ms, one `ps` snapshot identifies
the owned process tree and sums RSS; macOS `proc_pid_rusage` supplies successfully
sampled physical footprints. Each matrix command has a 120-second deadline and
1536 MiB tree-RSS and physical-footprint cutoffs. Sampled bounds can miss short
peaks, and RSS can count shared pages twice. Whole-command peaks include both
direct windows, bootstrap, verification, reporting and cleanup; they cannot be
assigned to either window. BEAM total/process/binary/code/ETS values are point
snapshots, not allocation totals or guaranteed peaks.

The predeclared serial matrix contains 72 plain fixture commands (three trials
per scope/mode), 24 diagnostic fixture commands (one per scope/mode), nine plain
native commands and nine diagnostic native commands (three per native scenario).
Case order rotates across trials. Diagnostic runs are separate from plain
timings; their wrappers and source compilation add overhead. They record nine
phase labels and aggregate runtime-call count/time per process. Nested spans
are inclusive and must not be summed. Sort spans by timestamp and PID: ETS
insertion keys are not chronological across processes. Direct window boundaries
and native init/stop boundaries identify the corresponding activation.

`install_us` measures elapsed time inside each runtime call, including any
scheduling or synchronization delay. It does not profile runtime internals or
prove a particular lock mechanism. The pattern phase minus runtime-call time
also includes instrumentation and bookkeeping. Completion retirement can call
the same runtime function later; startup attribution uses only startup spans.

Preferred native QA uses clean, warmed Ecto
`11784f821a1bb0eedeee59583e311d836cb39ee1` and Livebook
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`, without modifying their sources,
dependencies, tests or timeouts. Normal Mix/ExUnit execution uses both default
checks, seed 922331, max_cases 4 and max_requires 14. Scenarios are full Ecto,
Livebook's NodeManager test at line 8, and full Livebook. Native test identities,
required paths, failures, compiler options, overlapping timings, raw coverage
and rendered reports are retained. Offline decoding is outside timed commands.
Previously assessed Realtime/LiveView pins have incompatible toolchains and
are not upgraded or shimmed for this study.

Run from `packages/bylaw_contract`, with clean compatible external clones and
new output directories:

```sh
MIX_ENV=test mise exec -- mix compile
mise exec -- elixir qa/trace-activation-fixtures.exs /tmp/trace-fixtures
mise exec -- python3 qa/run-trace-activation.py fixture \
  _build/test/lib/bylaw_contract/ebin /tmp/trace-fixtures /tmp/trace-plain \
  --ecto "$ECTO" --livebook "$LIVEBOOK" --trials 3
mise exec -- python3 qa/run-trace-activation.py fixture \
  _build/test/lib/bylaw_contract/ebin /tmp/trace-fixtures /tmp/trace-diagnostic \
  --ecto "$ECTO" --livebook "$LIVEBOOK" --trials 1 --diagnostic
mise exec -- python3 qa/run-trace-activation.py native \
  _build/test/lib/bylaw_contract/ebin /tmp/trace-fixtures /tmp/trace-native \
  --ecto "$ECTO" --livebook "$LIVEBOOK" --trials 3
mise exec -- python3 qa/run-trace-activation.py native \
  _build/test/lib/bylaw_contract/ebin /tmp/trace-fixtures /tmp/trace-native-diagnostic \
  --ecto "$ECTO" --livebook "$LIVEBOOK" --trials 3 --diagnostic
```

## Direct results

All 96 fixture commands pass, yielding 192 complete windows. Each scope/mode
has one full coverage fingerprint across plain/diagnostic runs, three plain trials
and first/repeated windows. Exact events, selection, caller identities, source
module MD5s, cleanup and the default 4096 guard are verified throughout.

Three-trial plain medians follow for both call and return interests. Memory
peaks cover the whole two-window command. Complete per-mode ranges, stop/workload
timings and memory snapshots remain in the results artifact.

| Selected functions | First start, ms [range] | Repeated start, ms | Repeated bookkeeping, ms | Tree RSS, MiB | Footprint, MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| 0 | 3.69 [3.62, 4.59] | 0.06 | 0.004 | 91.1 | 82.6 |
| 64 | 25.99 [24.53, 26.27] | 19.73 | 0.013 | 96.7 | 84.8 |
| 256 | 86.75 [82.99, 97.13] | 90.80 | 0.034 | 96.2 | 84.6 |
| 1,024 | 344.79 [301.58, 476.62] | 341.85 | 0.108 | 100.5 | 88.9 |
| 4,096 | 1395.75 [1391.09, 1398.23] | 1376.40 | 0.426 | 121.9 | 110.4 |
| 8,192 | 2717.26 [2459.33, 2751.49] | 2730.89 | 0.849 | 180.7 | 172.3 |

At 8,192 selected functions, call-only/return-only/both/mixed first-start
medians are 2.652/2.788/2.717/2.593 seconds; repeated medians are
2.723/2.757/2.731/2.702 seconds. Repeating a session still reinstalls the same
patterns. Small differences between interest modes are descriptive observations,
not established improvements. Three samples give ranges, not confidence intervals.

Across all 40 nonempty diagnostic windows, 99.34–99.79% of measured pattern
configuration time is inside the runtime calls. At 8,192 functions, both-interest
configuration takes 2.760/2.775 seconds for first/repeated windows; runtime-call
time accounts for 99.70/99.68%. The residual is 8.15/8.89 ms and includes
instrumentation. Comparable uninstrumented repeated bookkeeping takes 0.849 ms.
These numbers leave little demonstrated opportunity in the existing set loop;
they do not promise a speedup equal to the residual.

## Native results and attribution

All 18 native commands and 18 offline decoders pass. Each scenario preserves
its exact native test inventory and required-file list across plain/diagnostic
trials: 1,591 passing Ecto tests; one passing isolated Livebook test; or 1,511
passing full Livebook tests with 185 existing exclusions. All six isolated
observations are complete and have identical full coverage and rendered-report
hashes. All 12 full-suite observations are explicitly incomplete at the unchanged
4096-message queue guard. Their wall times do not establish complete-suite
throughput or an optimization. No formal command crosses its deadline or sampled
memory cutoffs.

Plain three-trial medians follow; diagnostic timings are not mixed into them.

| Native scenario | Wall, s [range] | Init, s | Stop, ms | Tree RSS, MiB | Footprint, MiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ecto full | 8.91 [8.29, 8.95] | 7.721 | 6.7 | 664.9 | 675.3 |
| Livebook isolated | 10.52 [10.18, 10.99] | 8.153 | 30.4 | 716.1 | 644.9 |
| Livebook full | 17.71 [17.49, 18.05] | 9.553 | 15.3 | 931.2 | 913.8 |

Diagnostic three-trial medians isolate the two default workers. Counts are
requested exact call/return/union MFAs; they are not inferred counts of matched
runtime functions. The native runtime-call wrapper does not record each return
value. The direct fixture verifies every requested target independently.

| Scenario / check | Calls / returns / patterns | Activation, s | Pattern phase, s | Runtime calls, s | Runtime share of pattern phase |
| --- | ---: | ---: | ---: | ---: | ---: |
| Ecto full / Typespec | 184 / 45 / 184 | 0.057 | 0.051 | 0.051 | 99.64% |
| Ecto full / FunctionClauses | 1223 / 0 / 1223 | 0.373 | 0.372 | 0.371 | 99.71% |
| Livebook isolated / Typespec | 758 / 296 / 784 | 0.293 | 0.284 | 0.283 | 99.71% |
| Livebook isolated / FunctionClauses | 3693 / 0 / 3693 | 1.260 | 1.260 | 1.256 | 99.71% |
| Livebook full / Typespec | 758 / 296 / 784 | 0.293 | 0.284 | 0.283 | 99.70% |
| Livebook full / FunctionClauses | 3693 / 0 / 3693 | 1.332 | 1.331 | 1.327 | 99.69% |

Worker activation and its pattern phase are nested inclusive intervals. Their
difference includes session creation, process tracing, budget startup and
bookkeeping; all individual spans and ranges remain in the artifact. Native
activation confirms the fixture attribution without making an instrumented-run
speedup claim.

Every native capture reports released workers/shadows/sessions, zero fallback
stops and only the legacy trace session remaining. Isolated Livebook retains
`compiler_options_restored: false`, matching the earlier disabled NodeManager
control: its lifecycle changes `ignore_module_conflict`. The original flag is
preserved; see `preparation-overlap-2026-09-06.md`. No observer cleanup defect is
inferred from that pre-existing application behavior.

## Bounded parallel-installation control

The documented [trace function interface](https://www.erlang.org/doc/apps/kernel/trace.html#function/4)
accepts one exact MFA or broader wildcard forms. It does not document an
exact-MFA-list batch API. Wildcards can broaden selected scope, so they are not
adopted as an equivalent optimization.

A separate exploratory control installs the same 8,192 exact local call-only
patterns sequentially or through 2, 4 or 8 balanced tasks. Three trials rotate
worker count within one VM. Timed work includes chunking, task startup and
waiting, but excludes session creation, verification and workload. Every
requested pattern is verified; implicit module-info exports remain untraced.
Ten smoke calls per trial retain exact events and caller identity, followed by
session destruction. This is not full-observer or full-native equivalence, and
the trials are not independent fresh VMs.

| Installation workers | Median seconds [range] |
| --- | ---: |
| 1 | 2.459 [2.337, 2.475] |
| 2 | 2.466 [2.448, 2.481] |
| 4 | 2.477 [2.446, 2.482] |
| 8 | 2.429 [2.421, 2.554] |

All 12 cases pass. Overlapping ranges and small mixed differences do not justify
production concurrency. The whole exploratory command takes 29.86 seconds,
280.48 CPU seconds and 86.8 MiB sampled peak RSS. It uses the 120-second and
1536 MiB RSS guards, without a physical-footprint guard. The retained
`trace-activation-parallel.exs` is a formatted copy of the measured source;
their parsed ASTs match after removing source-position metadata. A final explicit
format check required only argument wrapping in that file. The formal-matrix
version remains in `parallel-formal-version.exs` with the original manifest hash;
the artifact records both source hashes and the formatting-only difference.

```sh
mise exec -- elixir -pa /tmp/trace-fixtures/ebin \
  qa/trace-activation-parallel.exs /tmp/trace-fixtures/config.json /tmp/trace-parallel.json
```

## Correctness, unsuccessful attempts and review

Five acceptance tests first ran as named empty tests, then failed with the QA
check absent, then passed with it present. They exercise selected public/private
functions and default arities, caller identity across independent sessions,
return-only patterns and completion retirement, failed-start cleanup preserving
an existing observer, and diagnostic phase coverage. A sixth test was inventoried
and added after review to run the actual scaling probe through two nonempty
observation windows.

Independent review reproduced two critical harness defects before the formal
matrix. Diagnostic matching recognized only do-only function bodies, omitting
the rescued create-session and configure-session phases. Preserving the complete
body keyword list inside an explicit try made the unchanged regression pass.
The scaling workload also used a claims accessor after activation had consumed
those claims; a one-function regression failed with KeyError. A worker-state
barrier returning `:ok` fixes that regression. Both red logs, frozen faulty
sources and unchanged green regressions are retained. The reviewer's original
phase JSON was overwritten during its green rerun; the red log and frozen source
remain, and the original JSON is not claimed as retained evidence.

The reviewer independently exercised eight semantic tests against both original
BEAMs and instrumented TraceWorker: local/private/global selection, initial
return-only patterns, retirement, four simultaneous independent sessions with
three caller PIDs and peer stop, failed activation, a 6,000-call overload at the
default 4096 guard, and an empty plan. All pass. These custom-check tests do not
exercise structural shadow allocation; the separately reproduced and deferred
`bylaw-contract-isolate-concurrent-shadow-allocation` remains unresolved.

Eight pre-matrix smoke commands and two native decoders pass. Their source
snapshots are retained separately because the final probe subsequently added
absolute start/stop boundaries for unambiguous phase matching. Smoke timings are
not mixed into formal summaries. All raw material is under
`/tmp/bylaw-trace-activation-20260906`; `trace-activation-results.json` retains
per-trial results, manifests, derived statistics and evidence hashes.

The final independent audit verifies all 114 planned rows, exact fixture hashes,
phase/window nesting, native inventories and cleanup. It independently decodes
all 18 native ETFs and re-renders their reports from each captured native working
directory, reproducing every hash. The reviewer's first re-render attempt used
the package working directory and failed on relative report paths; that setup
error's original script/log and the corrected passing audit are retained. It
did not require changing or rerunning native captures. A separate independent
calculation checks all 502 statistic groups and the artifact's expanded rows and
manifests against their raw originals. No remaining reproduced critical finding
was identified.

Repository-wide `scripts/qa.sh` passes, including all 974 UI tests. Explicit
format checks also pass for all new QA Elixir scripts. Production source remains
identical to the baseline; no other deferred investigation is activated.
