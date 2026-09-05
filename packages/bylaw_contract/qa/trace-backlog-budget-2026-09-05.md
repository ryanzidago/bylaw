# Default-check trace backlog budget

Beads: `bylaw-contract-bound-default-trace-backlog`.
Base revision: `86e784c77ab6e89acce65235729a4f4ed1264c22`.
The baseline library is identical to `f8cb8ec6852e4e5b6a38cad7b3635ba4813829ed`;
the intervening PR added profiling artifacts only.

Default checks previously queued full argument and return terms without an
observation budget. This change adds `max_trace_queue`, a positive integer with
a default of 4,096 messages per active check worker. A small independent guard
checks mailbox length every 5 ms; the worker also checks before consuming each
trace event, including the current event in its count. The guard does not copy
payloads or check state. Each guard owns only its worker/session references,
limit, and one shared overflow counter.

Exhaustion permanently destroys that isolated trace session. Already sent
messages can remain queued until the worker resumes or stops, but subsequent
calls and in-flight returns cannot replenish the destroyed session. The worker
discards remaining trace events, retains partial check data, and runs normal
check cleanup. The result carries `status: :incomplete` and reasons identifying
the check, limit and observed count. Summary/report output declines gap
assessment for the incomplete observation. Successful coverage and reports keep
the existing format. No application configuration or global system monitor is
used, and application execution continues normally.

This is an overflow policy, **not a hard byte-memory limit**. Mailboxes include
control messages; payload sizes vary, and scheduling can permit overshoot before
detection. Destroying a session cannot reclaim messages already sent to a
paused worker. The OS measurements below deliberately preserve these limits;
a small queue threshold does not imply a small transient memory peak.

## Regression and lifecycle evidence

Ten runnable acceptance tests cover independent Typespec/FunctionClauses
exhaustion, the default check pair, exact successful call/return/arity counts,
coverage/report/ETF equality, incomplete reporting, repeated cleanup, in-flight
returns, test-process rediscovery, and the bounded workload with default options.
The initial seven tests failed before the change: six rejected the missing
option, and the persisted-BEAM default case collected the burst without an
incomplete status. Fixtures explicitly enable debug information and reload the
persisted module; non-nil trace sessions are asserted.

An additional regression exposed a flaw in the initial implementation: disabling
process flags alone allowed later ExUnit process discovery to enable tracing
again. The failing control recorded `{:flags, [:call]}` after exhaustion.
Permanent session destruction fixes this, including races with deferred pattern
configuration. An intentionally destroyed session skips its cancelled delivery
barrier; unrelated configuration errors still propagate. Guards stop before
ordinary session teardown, and worker/check cleanup remains synchronized.

The initial 1,024-message default also interrupted the bounded 1,000-call return
fixture and the approved projects. A new default-workload regression failed
with that setting. The chosen 4,096 default accommodates the fixture and
Phoenix's observed burst, while still reporting larger backlogs explicitly.
Livebook exceeds this threshold; its outcome below is intentionally incomplete.

## Serial synthetic matrix

Elixir 1.20.2 / OTP 29.0.3, macOS. Each fresh VM executes three cycles of 1,000
calls with a 2,048-integer list and a payload-bearing union return. Variants are
the unchanged library, candidate limit 64, and candidate limit 4,096. Each runs
Typespec-only, FunctionClauses-only and default checks, with running, paused and
independently delayed consumers (10 ms paused / 2 ms active), three repeats.
The 81 trials therefore contain 243 cycles. Producer code is unchanged across
consumer speeds. No workload was increased to force exhaustion.

| Variant | Complete cycles | Incomplete cycles | Maximum sampled OS footprint, bytes |
| --- | ---: | ---: | ---: |
| Unchanged library | 81 | 0 | 265,995,008 |
| Candidate, limit 4,096 | 81 | 0 | 263,013,144 |
| Candidate, limit 64 | 0 | 81 | 250,217,216 |

Every trial exited successfully under the existing 384 MiB sampled macOS
physical-footprint watchdog. That watchdog samples every 20 ms and has a
60-second process timeout; it is not a kernel-enforced maximum allocation.
BEAM memory and worker queues are separately recorded at lifecycle boundaries.
All 162 complete cycles have exact counts and identical normalized coverage
and report hashes within each mode (54 comparable cycles per mode). All 81
low-budget cycles, including running consumers, report explicit incomplete
status and suppress missed-target diagnostics. ETF round trips are checked for
both outcomes. Low-budget timings cannot be treated as equivalent-workload
speedups because those observations stop early.

`trace-backlog-budget-results.json` retains compact grouped results, queue and
memory observations, cleanup ranges, and successful coverage/report hashes.
Raw captures remain outside the repository. The preceding exploratory matrix
used process-flag disabling; only `matrix-final` supplies this table.

## Approved repository QA

All runs use Elixir 1.20.2 / OTP 29.0.3, seed 922331 and max_cases 28, with all
three checks through `candidate-capture.exs`. Source and tests in both approved
checkouts remain unchanged. Runs were serial, without other owned heavy QA.

| Repository and pinned revision | Final test result | Final Bylaw observation |
| --- | --- | --- |
| Phoenix `1e6183e9ebab9994cf6e43d3af445f32664cc10c` | 1,087 passed; 33 excluded | Complete, default budget |
| Livebook `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | 1,511 passed; 185 excluded | Incomplete: Typespec observed 4,124 queued messages; FunctionClauses 4,098; limit 4,096 |

Phoenix excludes `mix_phx_new`. Livebook uses its existing exclusions:
`[python: false, git: true, fly: true, teams_integration: true, unix: false,
k8s: true, erl_docs: false]`. Passing Livebook tests is application compatibility
evidence, **not a complete coverage assessment**. The existing
`bylaw-contract-investigate-qa-overhead` investigation owns further work on its
consumer throughput; raising the queue threshold permits more retained memory.

An earlier Phoenix run with explicit limit 4,096 had complete observation but
one failing telemetry test. `RoutingTest` consumed `ResourcesTest` metadata
because its global handler forwards all router events and its first receive
pattern filters only `/users/:id`. A deterministic probe with Bylaw unloaded
reproduced that ambiguity by calling the foreign router first; the correct
RoutingTest event remained queued behind it. This is recorded separately as
`bylaw-qa-phoenix-telemetry-test-isolation`. Instrumentation can affect timing;
the final passing run does not erase the earlier failure. No upstream test was
patched and concurrency was not reduced.

## Reproduction and validation

From `packages/bylaw_contract` in a dedicated Bylaw worktree:

```sh
profile_root=$(mktemp -d /tmp/bylaw-backlog.XXXXXX)
mkdir "$profile_root/base-src" "$profile_root/base-ebin"
git -C ../.. archive 86e784c77ab6e89acce65235729a4f4ed1264c22 packages/bylaw_contract/lib \
  | tar -x -C "$profile_root/base-src"
mise exec -- elixir -e '
  [root, out] = System.argv()
  {:ok, _, _} = Kernel.ParallelCompiler.compile_to_path(
    Path.wildcard(Path.join(root, "packages/bylaw_contract/lib/**/*.ex")), out,
    return_diagnostics: true)
' "$profile_root/base-src" "$profile_root/base-ebin"
mise exec -- mix compile
mise exec -- python3 qa/run-trace-backlog-budget.py \
  "$profile_root/base-ebin" _build/dev/lib/bylaw_contract/ebin "$profile_root/matrix"
mise exec -- elixir qa/compare-trace-backlog-budget.exs \
  "$profile_root/matrix" "$profile_root/results.json"
```

Decode only trusted local ETF files. The verifier checks exact manifest trial
identities/configurations/cycle counts, successful OS exits, complete-vs-aborted
expectations, and equal successful coverage/report hashes. The profiler itself
asserts exact per-function counts, cleanup and round trips. External QA follows
the build/capture procedure in `candidate-audit-2026-09-05.md`; the capture
wrapper additionally accepts `BYLAW_AUDIT_MAX_TRACE_QUEUE` for explicit budget
experiments. Final captures use the library default.

Validation: 136 package tests passed on Elixir 1.20.2 / OTP 29.0.3; all ten
focused acceptance tests passed on Elixir 1.19.5 / OTP 28.3. The latter emitted
existing compiler-mapper API warnings; those unchanged helpers are outside this
trace-transport change. Strict Credo and the full `scripts/qa.sh` repository gate passed. The commit
and push hooks repeat that gate.

Session-local evidence: `/tmp/bylaw-backlog-qa/{matrix-final,results-final.json}`,
`{phoenix,livebook}-final.{log,etf}`, `phoenix-4096.{log,etf}`,
`phoenix-telemetry-probe.{exs,log}`, and `otp28.log`. Red/green acceptance logs
are `/tmp/bylaw-backlog-{red,reactivation-red,reactivation-flags,default-red}.log`
and `/tmp/bylaw-backlog-suite-final.log`. These are locators, not durable
prerequisites; the pinned source and committed helpers reproduce the evidence.
