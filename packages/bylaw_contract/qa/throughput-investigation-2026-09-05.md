# Contract observation throughput investigation

Bead: `bylaw-contract-recover-complete-qa-observation` (in progress).
Base: `a0d13bb9934996bf5e5e1c26b0792a848b51347f`.
Approved Livebook: `f18f2035bac89d6c08497f5f2d7e7c4f56e80716`.
Runtime: Elixir 1.20.2 / OTP 29.0.3, seed 922331, max_cases 28, existing QA exclusions unchanged.

## Current implementation candidate

Structural classification now returns its existing generated tuple directly. The check accumulates counters while walking clauses and outcomes together, removing intermediate per-call outcome maps. The public Contract interface and 4096-event queue guard remain unchanged. Three new preservation tests were inventoried empty and run, then implemented and passed against the unchanged library before editing behavior. All 143 package tests pass after the change.

The synthetic kernel performs 100,000 identical calls against five authored clauses in each of three trials. Baseline times: 91.246/85.037/84.687 ms. Compiled candidate: 56.900/54.458/52.981 ms. Baseline reductions: approximately 20.7 million; candidate: 8.5 million. Every trial retains exactly 100,000 calls and the same complete coverage SHA-256 (`142A8CB833D43835F865A8A090AFE544D3FD4BA4E8E490EDAFA18658EBEDEC21`). This narrow benchmark does not prove full-suite throughput. The candidate's full structural Livebook run passes all 1,511 tests but aborts observation at 4,099 queued events.

## Capacity controls

Diagnostic formatters and captures are retained in `/tmp/bylaw-throughput`. No Livebook sources or tests were edited. Diagnostic controls that skip classification are **not coverage evidence**: their zero counters cannot be interpreted as observed or missed targets.

| Experiment | Queue allocation | Result |
| --- | --- | --- |
| Sampled original typespec | 4096 | 1511 tests pass; abort at 4103; processed 36,261 calls and 7,593 returns |
| Sampled original structural | 4096 | 1511 tests pass; abort at 4206; processed 20,489 calls |
| No-op typespec consumer | 4096 | No queue abort; one FileGuard test fails; classification deliberately skipped |
| No-op structural consumer, three trials | 4096 | All tests pass; abort at 4105/4219/4306 despite skipping classification |
| Four module partitions, actual candidate counting | 1024 each, 4096 total | All four abort at 1864/1471/1049/1991; 1510 tests pass, one HomeLive test fails |
| High-priority actual candidate consumer | 4096 | All tests pass; abort at 4222 after 21,156 calls |

Queue observations can overshoot between checks, as documented by the existing guard. The four-partition probe retains exactly the baseline 5,246 clauses, 3,693 arities and 355 structural modules, each assigned once. Its 193,694 observed calls are partial; they are not comparable to a complete full-suite count. Static per-partition limits can also leave unused capacity in other partitions. Neither partitioning nor priority changes were adopted in production.

Process.info sampling every millisecond captured stack traces, queue lengths, reductions and memory. Only 36 structural and 47 typespec samples had nonempty queues; this is too sparse to claim a dominant CPU cost. Sampling itself affects execution, so these runs are diagnostic rather than speed comparisons.

The no-op controls show that structural bursts can overwhelm the current transport even without classification work. They do not establish a universal capacity limit or prove payload copying is the cause. A further counted no-op consumer compared full-argument and arity-only messages. Both aborted: full arguments at 4952/4096 after 156,560 diagnostic events; arity-only at 4116/4096 after 128,868 events. The full-argument run had a missing-personal-hub test failure; arity-only passed all tests. This does not isolate copying cost quantitatively, but shows that removing argument payloads alone did not prevent overflow in this sample. Neither diagnostic provides structural coverage. Complete full-suite observation, exact counter preservation under a transport change, repeated cleanup and bounded-resource QA remain unproven; this issue is not complete.

## Retained evidence

- `sample-capture.exs`, `run-samples.py`, `samples-results.json`, `typespec.etf`, `structural.etf`, per-worker sample ETFs and `sample-summary.log`: initial diagnostic runs.
- `structural-kernel.exs`, `kernel-baseline.log`, `kernel-fused.log`, `kernel-candidate.log`: baseline, exploratory and compiled-candidate kernels.
- `acceptance-inventory.log`, `acceptance-baseline.log`, `candidate-tests.log`: runnable inventory, baseline preservation and package test results.
- `structural-candidate.etf` and `.log`: actual candidate full-suite run.
- `drain-capture.exs`, `drain-{typespec,structural}.etf`, `drain-{2,3}-structural.etf` and adjacent logs: no-op consumer controls.
- `partition-capture.exs`, `partition4-structural.etf`, `partition-summary.exs`: four-partition experiment and exact metadata comparison.
- `priority-capture.exs`, `priority-structural.etf` and `.log`: scheduling-priority control.

The new FileGuard and HomeLive failures are retained without causal attribution. Existing QA failure investigations remain separate from throughput improvements.

## Native call-volume control

The corrected native call-counter diagnostic captured 1,321,799 calls across available structural targets in 6.273749 seconds, with all 1,511 tests passing and 185 excluded. Counters were native `:trace.function/4` call counts, paused before reading; no per-call messages or clause classification were performed. Only 44,695 calls were to targets without authored clauses, about 3.4% of the recorded volume. `Livebook.Intellisense.Elixir.Docs.render_blockquote/1` was unavailable for native tracing, consistent with the existing eliminated-function investigation. No claim of complete clause coverage follows from these counters.

The validated artifact is `/tmp/bylaw-throughput/native-count-v5-structural.etf`; `native-summary.exs` and `native-summary.log` retain totals and the busiest MFAs. Earlier v1–v4 full or isolated runs produced no capture because formatter initialization could not locate StructuralCoverage after Mix changed the code path. ExUnit continued after the formatter startup error. Restoring the Bylaw path inside initialization fixed the failure; the driver now requires a terminal capture. A separate synthetic smoke check recorded exactly ten native calls. The earlier missing-capture runs provide no call-volume evidence.

## Shared aggregate-budget experiment

A temporary four-consumer prototype monitored the sum of the four mailboxes before each event and independently every five milliseconds. Its synthetic check allowed 1,025 messages in one partition, then verified that a combined 4,097 messages aborted all four sessions. The Livebook run passed all 1,511 tests and retained exactly the baseline target metadata, but aborted at an aggregate 4,136 events after retaining only 1,278 calls. This prototype adds cross-process queue inspection on the hot path and was not adopted. It does not establish that all possible parallel implementations must fail. Scripts and capture: `shared-budget.ex`, `shared-smoke.exs`, `shared-capture.exs`, `shared4-structural.etf`, and `shared-summary.exs` under `/tmp/bylaw-throughput`.

The production candidate remains only fused structural counter accumulation. `structural-count-kernel.exs` provides its reproducible microbenchmark with explicit library and fixture paths. Full observation recovery remains open; neither passing tests nor faster partial observation counts are evidence of complete full-suite coverage.

## Candidate preservation matrix

All 81 fresh-VM trials and 243 lifecycle cycles completed under the existing 384 MiB sampled OS-footprint watchdog. The verifier found 162 complete cycles with identical coverage and report hashes across baseline and candidate (54 each for typespec, structural and default checks). The remaining 81 low-budget cycles explicitly reported incomplete observations. Complete trials retained exact 1,000-call counts; repeated cleanup and paused-consumer overflow checks passed. Baseline omitted the queue option and therefore used its existing default 4096, not an unlimited buffer. `structural-count-semantic-results.json` retains compact results; full phase details are `/tmp/bylaw-throughput/semantic-results.json`. These bounded synthetic results support preservation of the counting optimization, not full-suite completeness.

Repository-wide `scripts/qa.sh` passed for this candidate; the complete log is `/tmp/bylaw-throughput/root-qa.log`.
