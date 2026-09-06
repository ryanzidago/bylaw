# Compilation and execution concurrency

Beads: `bylaw-contract-measure-test-concurrency-tradeoffs`, under `bylaw-performance`.
The measurements support workload-specific memory/latency controls in the QA
runner, with no production default change. Lower compilation concurrency reduced
sampled peak memory; both external suites still produced incomplete observations
at every setting. The shared wrapper also received a reproduced Linux portability
fix so normal acceptance tests do not require macOS timing utilities.

This investigation varies native Mix test-file compilation concurrency separately
from ExUnit case execution concurrency. Lower parallelism can change overlapping
allocations and trace bursts, but does not remove contract preparation or per-event
classification work. Library code, check defaults and queue budgets are unchanged.

## Measurement contract

The library revision is `338bfa74591b05fc014cfca929075fef6608d4fc` (following PR296),
Elixir 1.20.2 / OTP 29.0.3, ARM64 macOS, 14 online schedulers. The pinned installed
[Mix test compiler](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/mix/lib/mix/compilers/test.ex)
passes `--max-requires` to `Kernel.ParallelCompiler.require/2` as `max_concurrency`.
Its [native default](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/elixir/lib/kernel/parallel_compiler.ex)
is the online scheduler count, with a minimum of two; explicit one is permitted.
ExUnit separately controls concurrently running async cases with `--max-cases`.
On this machine the native values are 14 compilation workers and 28 cases.
Async group constraints and synchronous cases can further limit actual concurrency.

| Setting | Compilation limit | Case limit | Comparison |
| --- | ---: | ---: | --- |
| native | 14, no CLI override | 28, no CLI override | Native control |
| requires-1 | 1 | 28 | Compilation alone |
| requires-4 | 4 | 28 | Compilation alone |
| cases-1 | 14 | 1 | Execution alone |
| cases-4 | 14 | 4 | Execution alone |
| both-1 | 1 | 1 | Fully serial combination |
| both-4 | 4 | 4 | Modest parallel combination |

The matrix makes three passes through these settings. Pass two reverses both the
setting order and each disabled/enabled pair. All children run serially; this
session launches no competing heavy QA commands during measurements. Application
builds are warm, but every measured command uses a fresh VM. Checks are the exact
Typespec/FunctionClauses default pair against the entire selected application,
with the unchanged 4096-message guard. Seed 922331, test selection, source revision,
compiler options and test timeouts remain fixed. No `--slowest`, trace mode,
exclusions or raised limits are used as performance mitigations.

The generic application retains its twelve sign/choice classifier modules.
The same twelve async test modules now live in separate files, because one file
cannot exercise test-file compilation concurrency. Test names, loops, assertions
and expected events are unchanged. The previous warm-session helper was updated
to require all fixture test files, preserving its three loaded-module runs.

From `packages/bylaw_contract`, use the repository toolchain and fresh output paths:

```sh
MIX_ENV=test mise exec -- mix compile
mise exec -- python3 qa/run-concurrency-matrix.py fixture \
  qa/performance_phase_fixture /tmp/concurrency-fixture
mise exec -- python3 qa/run-concurrency-matrix.py ecto "$ECTO" /tmp/concurrency-ecto
mise exec -- python3 qa/run-concurrency-matrix.py livebook "$LIVEBOOK" /tmp/concurrency-livebook
mise exec -- python3 qa/run-concurrency-matrix.py fixture \
  qa/performance_phase_fixture /tmp/concurrency-fixture-diagnostic --diagnostic --trials 1
mise exec -- python3 qa/run-concurrency-matrix.py ecto "$ECTO" \
  /tmp/concurrency-ecto-diagnostic --diagnostic --trials 1
mise exec -- python3 qa/run-concurrency-matrix.py livebook "$LIVEBOOK" \
  /tmp/concurrency-livebook-diagnostic --diagnostic --trials 1
```

The existing phase runner accepts explicit positive `--max-requires` and
`--max-cases`, or `default` to omit that native CLI flag. Its old no-argument
behavior retains max_cases 4; the new matrix explicitly requests native defaults.
The acceptance tests reject zero/negative limits before any workload/output is
created. The normal formatter capture records actual ExUnit max_cases, scheduler
count and async/sync test counts. Diagnostic native-require spans record the
actual compiler limit and number of selected files, rather than inferring the
setting solely from a requested command line.

## Timing, memory and completeness

Each measured child has a 120-second deadline and 1536 MiB sampled process-tree
RSS cutoff. The wrapper samples simultaneous owned process-tree RSS about every
100 ms. Shared pages may be counted repeatedly and short peaks can be missed;
this is not a hard memory guarantee. Native `/usr/bin/time -l` provides command
wall time, CPU and a separate maximum-RSS counter. Python elapsed includes polling
and reaping, so tables use native `reported_real_s` for wall comparisons.

Every capture records initialization, observation-window, stop and native ExUnit
suite timings. Native `load: nil` means test loading overlaps execution and is
retained as null, not measured zero. Per-test times also overlap and cannot be
summed as suite wall time. Fixture build warmup is outside command timing and retained in a separate log;
ordinary command timing includes VM/app startup and shutdown.

One additional diagnostic per setting preserves the native Mix runner but wraps
preparation/activation/stop functions and the native require call with monotonic
spans. These runs also sample each registered check-worker mailbox every 5 ms,
retaining the observed peak and sample count. Samples are lower bounds, not the
true peak or solely trace-message counts. The unmodified budget's own exceeded
count remains in incomplete reasons. Sampling does not inspect queued payloads or
copy prepared metadata. Diagnostic instrumentation is excluded from normal timing
comparisons; its nested/overlapping spans must not be added as exclusive phases.

The complete fixture oracle requires exactly 20 calls/returns for each of twelve
Typespec targets, 20 structural calls for each of 24 functions, and independently
expected head/guard/selected outcomes for 48 clauses. A full-coverage fingerprint
checks the entire result, including target identities and findings. Disabled
controls explicitly verify that no Bylaw.Contract modules were loaded.

External runs use unchanged, clean approved checkouts: Ecto
`11784f821a1bb0eedeee59583e311d836cb39ee1` and Livebook
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`. Native test compiler options are
`docs: false`, `debug_info: false`, `infer_signatures: false`; Livebook's existing
`docs: true` override is preserved. Their full suites retain synchronous tests,
async tests and existing configured exclusions. Historical Realtime/LiveView
native toolchains do not meet current Bylaw's Elixir requirement and are not
upgraded as part of this task.

These application suites exercise live background and compilation activity, so
full-coverage fingerprints need not be identical when scheduling changes. They
are not the deterministic fixture oracle. Passing tests or exit zero alone do not
establish complete observation. Missing captures, test failures, invalid cases and
incomplete reasons are retained, and incomplete runs cannot justify a claim of
faster complete observation.

## Repeated unprofiled controls

Values below are medians with observed ranges across three fresh-VM trials.
They are small-sample observations on a shared machine, not confidence intervals.

### Generic fixture

| Setting | Disabled wall, s | Enabled wall, s | Enabled sampled peak, MiB |
| --- | ---: | ---: | ---: |
| native | 0.35 [0.34, 0.37] | 0.39 [0.39, 0.41] | 117.4 [117.3, 121.5] |
| requires-1 | 0.40 [0.39, 0.46] | 0.40 [0.40, 0.43] | 104.3 [96.7, 106.7] |
| requires-4 | 0.35 [0.35, 0.36] | 0.40 [0.40, 0.42] | 110.4 [109.0, 112.7] |
| cases-1 | 0.38 [0.35, 0.39] | 0.39 [0.39, 0.40] | 117.1 [117.1, 118.8] |
| cases-4 | 0.35 [0.34, 0.38] | 0.40 [0.40, 0.41] | 115.4 [112.0, 119.6] |
| both-1 | 0.40 [0.38, 0.40] | 0.41 [0.40, 0.43] | 100.1 [98.3, 108.0] |
| both-4 | 0.35 [0.35, 0.35] | 0.40 [0.39, 0.45] | 110.8 [99.3, 112.0] |

### Ecto full suite

| Setting | Disabled wall, s | Enabled wall, s | Enabled sampled peak, MiB |
| --- | ---: | ---: | ---: |
| native | 2.52 [2.52, 2.59] | 6.30 [6.26, 6.41] | 685.2 [623.1, 708.7] |
| requires-1 | 9.87 [9.86, 9.90] | 10.31 [10.29, 10.37] | 473.7 [446.2, 478.7] |
| requires-4 | 3.41 [3.36, 3.44] | 5.64 [5.61, 5.66] | 626.2 [586.7, 626.3] |
| cases-1 | 2.53 [2.51, 2.58] | 6.78 [6.56, 6.81] | 683.0 [671.2, 732.0] |
| cases-4 | 2.58 [2.52, 2.67] | 6.37 [6.32, 6.55] | 678.8 [672.9, 788.9] |
| both-1 | 9.89 [9.78, 9.96] | 10.44 [10.21, 10.56] | 471.6 [465.1, 479.0] |
| both-4 | 3.39 [3.31, 3.40] | 5.75 [5.62, 5.76] | 634.3 [616.6, 640.1] |

All 42 normal fixture commands execute twelve async tests; all enabled observations
complete and retain one identical full-coverage fingerprint across settings. The
smaller sampled peak with one compilation worker is repeatable in this fixture,
while enabled wall-time ranges overlap. There is no clear latency improvement.

All 42 normal Ecto commands pass 1,591 tests: 1,584 async and seven synchronous.
Every enabled observation remains incomplete at the unchanged guard. Compilation
limit one lowers median sampled peak from 685.2 to 473.7 MiB, while increasing
median wall time from 6.30 to 10.31 seconds. Execution limit one does not produce
the same memory reduction. Compilation limit four has lower observed latency and
peak than native, but these incomplete reports do not establish faster complete
observation or equivalent delivered counts.

Lower compilation concurrency also changes when async case modules become
available to ExUnit; holding the case limit constant does not hold actual test
parallelism constant. These are independent controls with interacting runtime
effects. The measurements do not isolate all memory savings to one allocation
phase, and no hard memory bound or intrinsic classification-cost reduction follows.

One Ecto diagnostic (`requires-1`) passes 1,590 tests and fails the repository-start
telemetry assertion in `test/ecto/repo/supervisor_test.exs:50`: it receives the repo
name from another async test instead of `:telemetry_test`. The async test's global
handler accepts any matching `Ecto.TestRepo` event. This supports a scheduling
interaction hypothesis, not a proven Bylaw defect. The failure remains in the
artifact, with deferred follow-up `bylaw-contract-qa-ecto-telemetry-isolation`.
No external test, timeout or concurrency declaration was modified to hide it.

### Livebook full suite

| Setting | Disabled wall, s | Enabled wall, s | Enabled sampled peak, MiB |
| --- | ---: | ---: | ---: |
| native | 7.20 [7.08, 7.45] | 13.03 [12.52, 13.58] | 932.2 [890.0, 994.2] |
| requires-1 | 13.46 [13.33, 13.53] | 14.14 [14.08, 14.26] | 799.6 [777.6, 821.5] |
| requires-4 | 8.02 [7.96, 8.07] | 12.35 [12.32, 12.45] | 773.6 [745.3, 876.2] |
| cases-1 | 11.20 [11.17, 11.57] | 18.17 [17.96, 18.43] | 858.3 [838.8, 938.3] |
| cases-4 | 7.08 [6.92, 7.16] | 13.33 [13.30, 13.34] | 912.2 [863.9, 992.0] |
| both-1 | 13.46 [13.42, 13.48] | 19.03 [18.98, 19.13] | 617.7 [612.7, 676.2] |
| both-4 | 8.03 [8.02, 8.04] | 13.39 [13.02, 13.46] | 820.5 [704.9, 834.2] |

Every Livebook command accounts for 1,696 tests: 1,666 async and 30 synchronous,
including the same 185 configured exclusions. All 21 disabled trials and 20 of
21 enabled trials pass the remaining 1,511 tests. Enabled native trial two passes
1,510 and fails the standalone-runtime connection assertion at
`test/livebook_web/live/session_live_test.exs:958`; its child log reports
`Livebook.Runtime.EPMD.start_link/0` undefined. This matches the existing deferred
`bylaw-qa-livebook-epmd-startup-race` family, without establishing causation.
The table includes that failed trial; no passing replacement was substituted.

All 21 normal and seven diagnostic enabled Livebook observations remain incomplete.
A compilation limit of four lowers median sampled peak from 932.2 to 773.6 MiB;
fully serial limits lower it further to 617.7 MiB but increase median elapsed time
from 13.03 to 19.03 seconds. These are tradeoffs for incomplete captures, not
validated equivalent-observation improvements. Limiting cases alone to one slows
the suite substantially and still does not restore complete observation.

## Diagnostic timelines and queue pressure

The table shows one diagnostic per setting, in seconds. `Load / overlap` is native
test-file require time and its intersection with formatter initialization. These
intervals overlap; neither their sum nor the sum of per-test durations is wall time.
Queue values are sampled maxima across the two check workers, not upper bounds.

| Setting | Ecto load / overlap, s | Ecto sampled queue max | Livebook load / overlap, s | Livebook sampled queue max |
| --- | ---: | ---: | ---: | ---: |
| native | 1.857 / 1.834 | 14555 | 1.857 / 1.835 | 7494 |
| requires-1 | 9.620 / 5.164 | 4312 | 10.096 / 8.583 | 5679 |
| requires-4 | 2.894 / 2.883 | 13580 | 3.080 / 3.065 | 6915 |
| cases-1 | 1.844 / 1.817 | 8238 | 1.978 / 1.956 | 4290 |
| cases-4 | 1.757 / 1.738 | 4466 | 1.929 / 1.907 | 4411 |
| both-1 | 9.621 / 5.132 | 4259 | 9.780 / 8.131 | 4450 |
| both-4 | 2.882 / 2.871 | 4677 | 3.042 / 3.026 | 4610 |

Native require diagnostics confirm all requested compilation limits, with 12
fixture files, 45 Ecto files and the fixed Livebook file selection recorded per
capture. Every queue-sampler PID matches an actual check activation span and has
at least one sample. The fixture samples see only 0–1 queued messages, which does
not prove that larger bursts never occurred between samples. All external
diagnostics remain incomplete, even where sampled peaks miss the guard crossing.
Their budget-exceeded counts and reasons are retained independently.

## Adoption decision and verification

The supported outcome is explicit caller-controlled memory/latency tradeoffs in
the QA runner. There is no universal setting and no change to Bylaw's production
checks, default scope, queue budget or orchestration. The complete generic fixture
supports lower sampled peak memory with lower compilation concurrency, but shows
no clear speed improvement. Both real application suites retain incomplete
observations at every tested setting; reducing concurrency does not solve their
complete-observation problem. Prepared-check reuse and producer-side changes remain
deferred. The separate open preparation/loading-overlap investigation can use
these timelines without assuming that overlap duration determines peak memory.

All 147 planned measurement commands completed and produced valid terminal
captures: 126 unprofiled and 21 diagnostic. None hit the external deadline or
memory cutoff. All 49 fixture captures pass the independent exact-count verifier;
the updated warm helper also runs three full suites and passes the same oracle.
Six new normal-suite acceptance tests cover concurrency controls, exact workload
preservation and resource-wrapper portability; fourteen focused new/existing tests
pass together. The inventories ran empty first, then exposed missing controls and
the portability failure before implementation.
The final repository-wide `scripts/qa.sh` passes, including 974 UI tests; both
external checkouts remain clean at their recorded revisions.

Independent review reproduced a real shared-wrapper portability defect: the
normal tests failed when `/usr/bin/time` was absent in an existing Linux image,
and BusyBox rejected macOS `-l`. The wrapper now uses the original macOS flags,
Linux-compatible formatted counters with KiB-to-byte conversion, or nullable native
counters when the optional timing tool is absent. Deadline and sampled-RSS controls
still run via POSIX process groups and `ps`. The exact Linux command reproduction
passes after the fix, as does the BusyBox format check; no full Linux Elixir-suite
pass is claimed. Unit regressions also verify deadline termination, nonzero child
status and metric units.

This portability correction followed the completed matrix. The measured macOS
invocation is unchanged, and original measured source hashes are retained rather
than rewritten to imply a later source revision was benchmarked.
`concurrency-results.json` keeps every command, pin, source hash, terminal outcome,
phase/queue capture and failure. Individual test timings are summarized; raw arrays
and ETFs remain under `/tmp/bylaw-concurrency-20260906`. The large Livebook HTML and
mailbox assertion payload is summarized with its SHA256; the original failure log
and capture remain available at `livebook/2-native/1-defaults.*` in that root.

The two measurement failures are retained, not attributed to Bylaw without a generic
reproduction. Ecto telemetry has a new deferred QA issue; the Livebook failure was
appended to its existing deferred issue. The earlier Worktrunk refresh UI timeouts
were likewise recorded in the existing deferred UI issue, followed by a successful
clean-worktree baseline QA run. No deferred issue was promoted or worked as a fix.
