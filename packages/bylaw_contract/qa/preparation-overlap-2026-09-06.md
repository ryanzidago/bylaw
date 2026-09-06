# Preparation and native test loading — 2026-09-06

Keep ordinary preparation/loading overlap. The QA serialization gate lowers
sampled peak RSS in these trials, but changes observation of application calls
executed while requiring test files. It therefore cannot replace the formatter
path while preserving general semantics. Full Ecto and Livebook observations are
also incomplete in both layouts. No production code, public API, application
configuration, queue limit or default changes.

This resolves `bylaw-contract-measure-preparation-test-loading-overlap` with a
rejected production integration and a retained bounded experiment. The separate
deferred preparation-bounding and prepared-state-reuse issues remain deferred.

## Boundary and correctness

The starting revision is `a257b54b65643c33c18eca958573acadc86862ee`, after
[PR 299](https://github.com/ryanzidago/bylaw/pull/299). Measurements use Elixir
1.20.2 / OTP 29.0.3, ARM64 macOS, 14 schedulers. Actual library, harness and BEAM
hashes, repository pins, commands and runtime output are retained in the data.

The pinned [Mix compiler](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/mix/lib/mix/compilers/test.ex)
starts `ExUnit.async_run()` before native `Kernel.ParallelCompiler.require/2`.
The QA wrapper replaces that require call in memory in both layouts. Normal
returns directly to native requiring; serialized waits for the original
formatter's `Contract.start` to finish. Application selection, two default checks,
native seed 922331, native max_requires 14 and max_cases 28 stay fixed. Compiler
options at require and formatter initialization are identical within each project:
docs/debug_info/infer_signatures false, except Livebook explicitly enables docs.
This wrapper supports the measured ordinary test path; it is not a supported Mix
compiler, empty-selection or `--profile-require` integration.

Preparation includes activation. Default checks observe all processes after
activation, including code that native requiring may execute. A reviewer added
one `BylawPhaseFixture.Classifier1.classify(1)` call before a test module. Both
layouts pass the same 12 tests, but normal records 20 calls and serialized 21.
The independent equality test fails against the proposed general equivalence.
The source and failing output are retained in the results artifact. This is a
candidate scope change; moving activation without defining a separate preparation
boundary is insufficient. No production change attempts to make that test green.

The matched fixture has no such test-file body calls. All six formal captures pass
the independent `verify-performance-fixture.exs` oracle: 12 native tests, 12
typespec call/return targets with 20 events each, 24 structural arity counters with
20 calls each, and all 48 clauses' exact selected/head/guard counters. Full coverage
and rendered report hashes are each identical across all six captures, including
source locations. A separate acceptance fixture verifies the first setup call is
captured in both layouts. The isolated Livebook NodeManager selection likewise
has identical full coverage/report hashes across all six runs and one passed test.
Those are conditional equivalence results, not evidence for arbitrary test files.

## Unprofiled comparison

Three alternating normal/serialized pairs per project run serially in fresh VMs,
with a 120-second deadline and 1,536 MiB sampled process-tree RSS cutoff per
command. The fixture is compiled before timing. All 24 planned commands finish
with exit 0, identical native inventories within each project, unchanged sources,
no deadline/RSS cutoff and no owned observer resources left. Ecto passes 1,591
tests per run. Full Livebook passes 1,511 with its existing 185 exclusions.
All twelve full external observations retain trace-queue-limit incomplete reasons;
their differing coverage/report hashes prevent complete-equivalent throughput
claims. No failed native tests are discarded from this matrix.

Median [minimum, maximum] across three unprofiled runs:

| Workload | Layout | Whole-command wall, s | Total CPU, s | Sampled simultaneous tree peak, MiB |
| --- | --- | --- | --- | --- |
| Fixture | Normal | 0.69 [0.68, 0.70] | 2.02 [1.95, 2.12] | 119.16 [116.94, 120.38] |
| Fixture | Serialized | 0.69 [0.68, 0.70] | 1.96 [1.81, 1.99] | 98.95 [98.23, 101.08] |
| Ecto | Normal | 8.21 [8.17, 8.53] | 30.86 [30.66, 31.17] | 633.34 [628.34, 683.91] |
| Ecto | Serialized | 9.94 [9.85, 9.97] | 34.98 [34.90, 35.01] | 581.89 [570.39, 613.81] |
| Livebook | Normal | 17.87 [17.63, 19.02] | 63.27 [61.76, 65.75] | 932.75 [924.34, 952.95] |
| Livebook | Serialized | 18.16 [18.01, 19.87] | 60.43 [59.38, 67.59] | 859.50 [857.27, 890.02] |
| Livebook NodeManager | Normal | 10.61 [10.61, 10.90] | 27.03 [27.00, 27.14] | 830.67 [803.27, 888.38] |
| Livebook NodeManager | Serialized | 10.41 [10.35, 10.70] | 27.05 [26.06, 27.07] | 751.81 [743.09, 807.92] |

Wall/CPU are native `/usr/bin/time` whole-command counters, including QA bootstrap
and teardown. Controller elapsed medians, including sampling/polling, are
normal/serialized 0.770/0.773, 8.239/10.019, 17.933/18.256 and 10.656/10.539 seconds.
RSS is the simultaneous sum over the process tree at 100 ms intervals; shared
pages can count repeatedly and short peaks can be missed. Three trials and these
sampled peaks do not establish a hard bound or precise small speed differences.

Normal preparation and requiring overlap for 12.0–14.8 ms in the fixture,
2,438.8–2,619.7 ms in Ecto, 2,414.4–2,825.5 ms in full Livebook and 13.9–18.2 ms in
the isolated test. Serialized overlap is zero in every run. Median preparation
normal/serialized takes 63.8/56.8 ms, 7,108.0/6,115.9 ms, 9,875.0/8,467.4 ms and
8,450.2/8,183.2 ms respectively. Earlier native loading competes with preparation,
but moving it later adds sequential work; Ecto's wall median increases 1.73 s.

## Memory interpretation

Every ordinary capture records BEAM total/process/binary/code/ETS memory at
preparation start/end, require start/end and stop start/end. Snapshots include
concurrent application activity and allocator effects; subtracting them does not
give an exclusive compiler-allocation or retained-check-state size.

For example, Ecto's median BEAM total at require completion is 185.0 MiB normal
versus 138.5 MiB serialized, but its pre-stop total is essentially unchanged at
117.0/117.5 MiB. Full Livebook instead has 241.3/256.3 MiB at require completion
and 222.6/224.5 MiB before stop. Isolated Livebook has 163.7/162.2 MiB before stop
and 92.1/90.6 MiB after stop. Median code memory there changes from 28.97 MiB
before stop to 28.24/28.25 MiB after stop. Serialization changes transient overlap;
it does not eliminate prepared metadata or generated code needed for observation.
The process-tree RSS differences are much larger than some BEAM snapshot changes
and must not be labelled exclusively as compiler storage savings.

Separate diagnostics time metadata loading, shadow forms/compilation, activation
and trace shutdown, and sample queues every 5 ms. The additional
`preparation-state-probe.exs` measures reachable check-state terms with
`:erts_debug.size/1` inside each owning worker, before activation and before
shutdown. It records process memory before walking the term and never copies the
prepared state into an observer. Term words exclude off-heap binary payloads,
generated code, other processes and allocator reservations. Worker process memory
includes heap slack and other runtime data; its difference from reachable state
is not an exact temporary-allocation measurement. These instrumented commands
remain separate from the unprofiled table.

All eight diagnostic commands pass with clean observer resources; full Ecto and
Livebook remain incomplete. Immediately after preparation, typespec/structural
reachable terms occupy about 0.025/0.021 MiB in the fixture, 1.107/1.045 MiB in
Ecto and 2.799/2.579 MiB in Livebook in either layout. Structural worker process
memory is 0.156 MiB in the fixture, 15.6/19.6 MiB in Ecto and 77.2 MiB in both
Livebook layouts. This distinction is substantial and remains after serialization.
The diagnostic state walk itself is expensive: `stop_trace` spans include that
walk and must not be used as uninstrumented drain timings. Ordinary stop medians
are 8.5/7.2 ms in Ecto and 47.8/50.7 ms in full Livebook. Sampled diagnostic worker
queue peaks are 0 for the fixture, 4,298/10,035 for Ecto, 10,274/6,068 for Livebook
and 1 for the isolated selection. These are diagnostic samples, not queue bounds.

## Integration and failure handling

The pinned [Mix test task](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/mix/lib/mix/tasks/test.ex)
invokes a configured coverage tool's `start/2` before application startup and
helper loading. Its returned callback runs after a successful require/run return,
including ordinary test failures, but is not a universal exception cleanup hook.
An adapter would need explicit target/module availability, a deliberate helper
and loading observation boundary, failure cleanup, and cooperation with the
existing coverage tool. It is not a drop-in location for current formatter setup.
The acceptance suite passes native `--cover` with this formatter gate; that proves
coexistence for the measured gate, not for an unimplemented coverage adapter.

Five named acceptance tests ran empty, then red against the missing probe, then
green. A report-hash assertion also ran red before capture was added. Initial
prototype tests exposed distinct temporary source paths and a gate waiting after
the formatter died during check initialization. Reusing the same fixture path
and monitoring the formatter owner resolved those harness defects. Two outer
60-second test timeouts and one explicit 15-second debug cutoff are retained in
local logs, outside formal timing rows. Acceptance child commands now have a
25-second external deadline that kills their owned process group.

The first repository-wide QA run exposed a further failure-path audit race: no
shadows or trace sessions remained, but a failed-start worker was still alive at
the immediate snapshot. The unchanged focused repeat passed. The final audit
waits up to two seconds for matching worker processes to exit and then reports
actual survivors; it neither kills them nor treats a timeout as clean. Focused
acceptance passes with that change. The ordinary and diagnostic measurements
precede this audit-only change; their exact measured probe source is retained
alongside its hash and the original QA failure.

Both normal and serialized initialization failures and native test-loading
failures retain nonzero outcomes and clean workers, trace sessions and generated
shadow modules. Initialization failure happens after a real structural shadow is
prepared. Normal loading failure may precede completed preparation; serialized
loading failure occurs after both check workers are prepared. All formal commands
finish without fallback stops, owned workers or shadows, with only the legacy
default trace session left. Compiler-option comparison against the pre-Mix VM is
reported separately from owned observer cleanup.

All six isolated Livebook audits record `compiler_options_restored: false`.
A separate native disabled-observer control passes the same test and retains
exactly `ignore_module_conflict: false -> true`, with NodeManager still alive.
The pinned NodeManager sets this for its lifetime and restores it on termination.
The full-suite audits restore the pre-Mix options. The isolated difference is
preserved, not treated as an observer leak or silently overwritten by the gate.

The temporary diagnostic controller initially rejected its `livebook-isolated`
label before launching that pair. Its initial source/error are retained; only the
unlaunched pair resumed using the manifest's `livebook` project key. A reviewer
also reproduced an invalid project label in the draft reproduction command as a
failing documentation test; the corrected command above passes that check.

## Reproduction and evidence

From a dedicated worktree, in `packages/bylaw_contract`:

```sh
MIX_ENV=test mise exec -- mix compile
mise exec -- mix test test/preparation_overlap_acceptance_test.exs
mise exec -- python3 qa/run-preparation-overlap.py fixture qa/performance_phase_fixture /tmp/preparation-fixture
mise exec -- python3 qa/run-preparation-overlap.py ecto /tmp/bylaw-compiler-cap/ecto /tmp/preparation-ecto
mise exec -- python3 qa/run-preparation-overlap.py livebook /tmp/bylaw-reasons.oRUJf0/livebook /tmp/preparation-livebook
mise exec -- python3 qa/run-preparation-overlap.py livebook /tmp/bylaw-reasons.oRUJf0/livebook /tmp/preparation-isolated --selection test/livebook/runtime/erl_dist/node_manager_test.exs
mise exec -- elixir qa/verify-performance-fixture.exs /tmp/preparation-fixture/*.etf
```

Use fresh output directories. `--diagnostic --trials 1` adds phase spans and queue
sampling. To include reachable-state diagnostics, load
`preparation-state-probe.exs` after `performance-phase-probe.exs` and before the
gate, with `BYLAW_PREPARED_STATE_OUTPUT` set. The retained diagnostic commands and
controller source show the exact invocation. The gate supplies require timestamps
because its native Mix wrapper supersedes the phase probe's Mix wrapper; library
phase wrappers remain active.

Ecto is pinned to `11784f821a1bb0eedeee59583e311d836cb39ee1`; Livebook to
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`. Incompatible preferred Realtime and
LiveView revisions remain excluded under the earlier runtime assessment; no
upgrades or external source changes were made. `preparation-overlap-results.json`
retains the manifests, individual native outcomes, timing/memory/timeline data,
coverage/report digests and exact native identities, diagnostics, and the reviewer
counterexample. Full logs and ETF captures remain in `/tmp/bylaw-overlap-20260906`.

Final repository `scripts/qa.sh` passes, including 974 UI tests. The reviewer
independently verified every retained formal/diagnostic row, artifact hash,
deduplicated inventory and table calculation. Its bounded cleanup-race attempts
did not independently reproduce the root QA failure; review confirms the wait
retains real survivors and does not weaken the resource checks.
