# Explicit ExUnit root ownership investigation — 2026-09-06

Do not replace scoped scanning with a production setup adapter yet. Synchronous
registration captures immediate test-root calls and avoids measurable scanning
work, but these bounded trials show little end-to-end improvement. A per-case
setup integration also requires caller changes and a deliberate narrower boundary
than arbitrary earlier setup or child-process ownership. No library source, API,
built-in check, queue limit or default scope changes in this investigation.

This resolves `bylaw-contract-investigate-explicit-test-process-ownership` with a
rejected production replacement and a retained QA prototype. The independent
correctness follow-up `bylaw-contract-define-scoped-early-call-boundary` is deferred:
current immediate scoped observation misses calls without an incomplete reason.
It is not a claim about the default `:all` checks.

## Runtime and scope

Bylaw starts at `17d81c9358fc421296af94318e536cf479468c00`, after
[PR 298](https://github.com/ryanzidago/bylaw/pull/298), using Elixir 1.20.2 /
OTP 29.0.3 on the same ARM64 macOS host. The manifest retains actual source hashes
and toolchain output. The following guarantees were checked against installed
source and the pinned
[ExUnit runner](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/ex_unit/lib/ex_unit/runner.ex),
[Case](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/ex_unit/lib/ex_unit/case.ex),
and [Callbacks](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/ex_unit/lib/ex_unit/callbacks.ex).

The runner publishes `test_started` before spawning the test process. It sets the
process label and `context.test_pid` before setup callbacks. `setup_all` and
`on_exit` run in different processes. The test supervisor carries ownership
metadata, but child startup must explicitly forward it; an ordinary spawned
process does not automatically carry universal test ownership.

Current `TraceWorker` scans `Process.list()` and active test labels immediately on
start notifications, then schedules a scan after 2 ms while labels are active.
The timer delay is not a guarantee of discovery within 2 ms: scanning, scheduling
and queued messages add delay. It retains discovered PIDs until the session ends.
Built-in checks omit the optional process scope and therefore use `:all`; none
requires this polling path.

| Boundary or process | Current `:ex_unit_tests` | QA explicit roots | `:all` control |
| --- | --- | --- | --- |
| Test setup/body after discovery or registration | Root PID traced | Root PID traced synchronously | Traced |
| Immediate first setup/body call | Discovery race; measured misses | Captured after registration | Traced |
| Earlier setup callback before adapter | May be captured if discovery has happened | Excluded | Traced |
| Recursive calls in test root | Captured after discovery | Captured | Captured |
| Concurrent parameter instances | Same label can identify distinct PIDs | Each `test_pid` registered separately | Captured |
| Nested tasks, ordinary spawn, supervised child | Not automatically selected by root label | Excluded unless caller adds separate registration | Captured |
| Pre-existing application worker | Excluded | Excluded | Captured |
| `setup_all` and `on_exit` | Excluded by test-root label selection | Excluded | Captured |

The QA adapter uses private `:sys.replace_state` access to disable scanning and
register roots against the **same existing trace worker and queue budget**. It
monitors roots and removes PID state on `DOWN`. It supports one named adapter per
VM and is not a supported integration or public library API. Both scoped modes
wait for pattern activation before tests begin, removing an initialization race
between the formatter's asynchronous activation and synchronous registration.

## Acceptance and independent oracle

Four normal-suite acceptance tests first ran as empty named cases, then failed
against the missing probe, then passed with the implementation. They check native
parameterized inventory, immediate caller-sensitive capture, scope distinctions,
failure/timeout cleanup and rejection after queue exhaustion. A further peak-root
assertion ran red before its counter was implemented. The initial diagnostic
wrapper failed to compile when a `try` had no catch/rescue/after; that attempt is
retained locally and excluded from timing comparisons. The corrected diagnostic
wraps only valid forms and preserves the original catch clause.

The generic suite has three test declarations parameterized over four lanes:
12 native tests, 12 distinct test-root PIDs, and at most four simultaneous roots.
The target function independently increments an ETS oracle on every actual
invocation. A custom check records call/return events with actual producer PIDs;
it has no typespec or structural classification cost and never retires interests.
Expected test names/lane pairs and exact aggregate counts are asserted separately.
Comparisons use per-PID, event-kind and recursive-depth call maps, not percentages.
Return totals must match call totals for each caller. A reviewer additionally
verified exact returned values and caller identities with a separate target.

The matched workload removes the earlier-setup call equally in both modes. It
executes 112 actual calls: 76 intended post-readiness root calls, four `setup_all`,
12 `on_exit` and 20 child-worker calls. The scanning control explicitly waits until
its root PID is traced; registration provides the corresponding readiness point.
Both capture exactly the same 76 calls: 12 setup, 48 body and 16 recursive calls.
This deliberate readiness gate makes it a conditional comparison, not ordinary
unmodified ExUnit latency. It cannot establish savings for default checks.

Separate immediate workloads retain all 124 actual calls, including 12 earlier
setup calls, and do not wait for scanner discovery. These quantify missed calls
and are **not used to claim speedups**. The all-process controls capture all 124,
including setup, descendants and pre-existing workers.

## Measurements

`run-ownership-investigation.py` records all 66 planned commands, running fresh VMs
serially with alternating scoped-mode order over three trials and 0, 1,000 or
5,000 idle processes. Each uses seed 922331, four ExUnit cases, the unchanged 4,096
queue limit, a 30-second external deadline and 1,536 MiB sampled tree-RSS cutoff.
The 63 ordinary commands comprise 18 matched, 18 immediate, 18 separate matched
scan diagnostics and nine all-process controls. Three further commands preserve
intentional failure, timeout and overflow behavior. Sources remain unchanged
through every measured command; no deadline or memory cutoff occurs.

Median [minimum, maximum] for the **unprofiled matched** commands:

| Idle processes | Mode | Native VM wall, s | Total CPU, s | Sampled process-tree peak, MiB | Native suite, ms |
| ---: | --- | --- | --- | --- | --- |
| 0 | Scan | 0.61 [0.60, 0.61] | 1.15 [1.11, 1.16] | 90.8 [90.8, 93.6] | 143.2 [142.0, 145.1] |
| 0 | Explicit | 0.60 [0.60, 0.61] | 1.09 [1.08, 1.11] | 90.2 [90.0, 90.8] | 137.0 [136.6, 137.1] |
| 1,000 | Scan | 0.63 [0.62, 0.65] | 1.28 [1.28, 1.38] | 95.0 [94.4, 96.6] | 143.3 [142.3, 144.4] |
| 1,000 | Explicit | 0.62 [0.60, 0.63] | 1.17 [1.08, 1.18] | 94.1 [92.5, 96.0] | 138.6 [137.5, 145.3] |
| 5,000 | Scan | 0.65 [0.64, 0.66] | 1.48 [1.39, 1.48] | 110.3 [104.9, 110.6] | 157.1 [154.4, 157.5] |
| 5,000 | Explicit | 0.65 [0.64, 0.66] | 1.33 [1.17, 1.38] | 103.8 [103.5, 107.6] | 139.1 [138.2, 139.6] |

Native wall/CPU are `/usr/bin/time` counters for the entire fresh-VM command,
including QA script compilation and cleanup. The controller also retains its own
elapsed time, including 100 ms process-tree sampling/polling delays. Its scan vs
explicit medians are 0.623/0.621, 0.743/0.738 and 0.746/0.751 seconds respectively.
Neither measure supports a substantial end-to-end win. Three trials do not provide
a precise estimate of small differences; there is no hard memory-bound claim.
Shared pages can count more than once in sampled aggregate RSS.

Worker queue/memory sampling runs every 5 ms in all modes. Matched plain scanning
queue peaks range from 17 to 41 messages; explicit peaks are zero in these samples,
not proof of zero transient queue occupancy. Worker memory samples range from
129.6–894.1 KiB for scanning versus 71.1 KiB for explicit roots. These include the
check's retained event list; they are not VM or total library resident memory.
Across 108 successful registrations in the nine plain matched explicit commands,
worker registration work takes a median 15 microseconds [7, 63], measured inside
the adapter around the worker operation. This excludes caller-to-adapter waiting.
There are 12 total roots per session, a peak of four, and zero retained explicit
root registrations before normal shutdown; scanning retains 12 until shutdown.

Separate diagnostic wrappers time scanning and are never pooled with plain runs.
At 0/1,000/5,000 idle processes they record respectively 53–54/43/26–27 scans and
33.4–35.9/58.6–63.2/115.0–116.7 ms total scanning work. Explicit roots execute zero
scans. Lower scan frequency at larger process counts reflects slower discovery,
not better throughput.

All nine immediate scanning runs miss promised root calls: 52 of 76 are retained
at 0 and 1,000 idle processes, and 48 at 5,000. Each loses all 12 immediate setup
calls and some body calls; no incomplete reason is returned. Explicit immediate
runs retain all 76 with caller-sensitive equality. This is evidence of a current
opt-in scope boundary problem, not evidence that its broader semantics have been
preserved by an adapter placed after earlier setup.

The two intentional failure/timeout commands each retain one failed native test
and exit 1. Their other 11 tests pass. The overflow command retains incomplete
reasons, rejects a later registration and does not reactivate tracing. Its native
tests pass, so this QA capture command returns 0 while explicitly recording the
incomplete observation; it is not a production formatter completion claim.
All 66 commands release owned tracer, check worker, budget watcher, adapter,
sampler, background fixture processes and trace sessions. Independent reviewer
repetition also verified three sessions in one VM, four concurrent roots per
session and normal/abrupt root exits with no retained registration state.

## Decision and reproduction

Keep this as an investigation. Even the 5,000-process conditional control reduces
suite time by only about 18 ms and sampled total peak by about 6.5 MiB. Whole-command
wall time does not improve there. The scoped scan cost is real, but there is no
repeated caller integration demonstrating that a new CaseTemplate/setup API is
worth its configuration and ordering contract. Registering descendants would need
additional caller-specific changes and would expand current root-only semantics.
Treat earlier setup and early-call correctness as the separate deferred boundary
issue; do not silently narrow observation or claim default-check savings.

From a dedicated linked worktree, in `packages/bylaw_contract`:

```sh
MIX_ENV=test mise exec -- mix compile
mise exec -- mix test test/ownership_probe_acceptance_test.exs
mise exec -- python3 qa/run-ownership-investigation.py /tmp/ownership-investigation
```

`ownership-investigation-results.json` retains the full plan, manifests, raw
per-caller fixture oracles/observations, native outcomes, timing/memory data,
cleanup checks and external QA records. Local logs and ETFs remain under
`/tmp/bylaw-ownership-20260906`. Repeated-session reviewer reproduction is in
that root's `reviewer/repeated_sessions_test.exs`. It changes no repository files.

## Preferred external QA

Both Ecto commands pass 1,591 tests at
`11784f821a1bb0eedeee59583e311d836cb39ee1`. The first disabled Livebook command
at `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` fails one existing
`AppLiveTest` assertion (`app_live_test.exs:86`): a just-deactivated session remains
rendered after the test receives its own update message. It passes 1,510 tests with
185 exclusions and exits 2. The default-check command passes all 1,511 with the
same exclusions. One unchanged disabled repeat also passes all 1,511. The original
failure remains in the data and existing deferred
`bylaw-qa-livebook-shared-state-failures`; no causal attribution or application fix
is claimed. Both external checkouts remain clean.

Enabled Ecto and Livebook observations remain incomplete at the unchanged 4,096
queue budget. These runs verify current library compatibility, not the unadopted
setup adapter in consumer applications. Historical Realtime/LiveView toolchains
remain incompatible with current Bylaw's Elixir requirement and are not upgraded.
External commands use `run-performance-phases.py`, one trial each, disabled/default
modes, seed 922331 and native max cases. All commands, pins and failures are retained.

Repository-wide `scripts/qa.sh` passes, including 974 UI tests. The independent
reviewer verified all 66 raw/packed captures, frozen source hashes, report
calculations, scope and cleanup, and all five external records. No reproducible
critical finding remains in this change.
