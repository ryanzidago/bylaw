# Native partitioned observation investigation — 2026-09-06

Issue: `bylaw-contract-investigate-partitioned-observation`, an open child of `bylaw-performance` when claimed. Bylaw revision: `cad426b631891f2dd937659b754c999b68b51362` plus the measured QA harness whose source hashes are retained in [the results](partition-observation-results.json).

## Decision

Native Mix file partitions can restore complete bounded observation for an across-file burst: all six four-partition fixture groups produced the independently expected counters and the same complete report. The single-VM and two-partition versions remained incomplete in every burst trial. This supports a caller-owned partition workflow for that workload, not a speed comparison against its incomplete baseline.

Keep the implementation in QA. The existing native Mix interface already partitions test files; these measurements do not justify a production scheduler, a public export/merge ABI, larger trace budgets, or a new default in `bylaw_contract`. The small complete workload gained little elapsed time from concurrent partitions while increasing CPU and simultaneous memory. Sequential partitions reduced its sampled median peak modestly at substantial elapsed cost, with overlapping memory ranges. Ecto and Livebook still had incomplete observation at two partitions. The deferred producer and prepared-state issues remain deferred.

For the complete burst work, concurrent4 had median wall 1.871 s versus sequential4 4.640 s, but simultaneous sampled RSS rose from 108.984 to 422.500 MiB. That is an explicit caller resource tradeoff. It does not establish a general application performance improvement.

## Scope and matching

The matrix contains 45 groups, 102 fresh native test VMs, and 45 separately timed postprocessing VMs. All 102 native commands and all 45 postprocessors exited zero, with no deadline or memory cutoff. Collection success is separate from completeness: only `merge.accepted` claims a complete aggregate. There were 21 accepted groups and 24 rejected incomplete groups.

Each workload ran three trials, reversing layout order in the second trial. The full group manifest, invocation UUID, code/BEAM hashes, runtime, commands, native file/test inventories, phase audits, outcomes, counters and resource measurements are retained in the results artifact. Source hashes were checked before and after every group. External repositories were clean before and after their runner. Nothing was recompiled or edited during the timed matrix, and no other benchmark VM ran alongside it.

- Runtime: Elixir 1.20.2, OTP 29.0.3 / ERTS 17.0.3, 14 schedulers per VM.
- Native options: seed 922331, max_cases 4 **per VM**, native max_requires 14. Thus concurrent2 permits up to eight cases and concurrent4 up to sixteen; this is not a fixed total scheduler/case budget experiment.
- Both default Bylaw checks, whole-application targets, normal preparation/loading overlap, process_scope `:all`, and each worker's unchanged 4096 trace-queue limit.
- Native test compiler options: debug_info false and infer_signatures false everywhere; docs false for the fixture/Ecto and docs true for Livebook, as explicitly configured by the pinned project's test options.
- Limits: 120 seconds and 1536 MiB sampled process-tree RSS per VM; 3072 MiB simultaneous native group limit. Postprocessing has its own 120 second/1536 MiB bound.
- Fixture: twelve files and twelve tests, one classifier per file. The ordinary workload uses ten iterations per file; the burst uses 300. Generated source is compiled before timing. Dependency installation, warmup, source fingerprinting and initial runner setup are outside the measured groups.
- Ecto: revision `11784f821a1bb0eedeee59583e311d836cb39ee1`, full native suite, 1591 passing tests. Two partitions contain 703 and 888 tests.
- Livebook: revision `f18f2035bac89d6c08497f5f2d7e7c4f56e80716`, full native suite, 1511 passing and 185 existing excluded tests. Two partitions contain 934 passing/105 excluded and 577 passing/80 excluded tests. Concurrent Livebook is deliberately unsupported by this runner because this checkout shares repository-relative log/data paths; unique TMPDIR does not isolate those resources.
- The previously preferred Realtime and LiveView revisions remain outside this compatible-runtime matrix; no dependency or toolchain upgrades were made to force them to run.

## Partition and observation semantics

Pinned [Mix test source](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/mix/lib/mix/tasks/test.ex) sorts the native test-file list and assigns files by zero-based index modulo N, selected using one-based `MIX_TEST_PARTITION`. It does not split work within a single file. The harness records the actual files passed to native `ParallelCompiler.require`, including files with no tests, and verifies each partition against this rule and the full reference test identity list (file, module, name and line). The [native test compiler](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/mix/lib/mix/compilers/test.ex) remains responsible for application/helper startup, requiring files and running ExUnit. Native line-coverage export is not a merger for Bylaw's observations.

Application startup and test-helper code that runs before formatter activation are outside this capture boundary. Application/background work after activation and per-VM setup can repeat. A separate acceptance workload adds exactly one known classifier call after activation in every VM: single observes 21 calls for that classifier, while two partitions aggregate 22, with the same native tests. The merger explicitly retains this repetition; it does not pretend partitioned startup is identical to one process or subtract unproven setup counts. The timed matrix uses bootstrap=0.

The pure QA merger sums raw nonnegative integer counters, recursively including clause outcomes, rather than averaging percentages or reusing the library's distinct-check merge semantics. It unions unknown targets and retains compatible target metadata, source identities and warnings. Compatibility requires schema 1, invocation/run identity, source fingerprint, runtime, partition count, iteration/bootstrap settings, native options, compiler options, target fingerprint, exact file inventory and exact test inventory. Missing, duplicate, failed, cut-off, unclean, incomplete and incompatible inputs cannot produce a complete merged capture. Rejection retains partition outcomes and incomplete reasons.

Every VM still prepares the full target set and two workers. Four fixture partitions therefore repeat preparation eight times at the worker level and retain four copies of runtime/module state; they do not partition instrumentation metadata. With four filesets, each burst VM observes three classifiers, 1800 classify calls plus 1800 returns, and 3600 structural calls. This smaller per-worker event volume explains the bounded result; it does not promise arbitrary burst handling.

The fixture oracle is independent of an observed baseline: it checks all 36 input classes, 24 return alternatives, 24 arities and 48 clauses, each selected/unselected classifier, positive/negative/zero categories, return alternatives and every structural outcome. It expects 240 classify calls, 240 returns and 480 arity calls in the small aggregate; the burst expects 7200, 7200 and 14400 respectively. Every complete partition and aggregate is checked. Incomplete reference captures anchor only metadata and native inventory, never an expected complete counter result.

## Measurements

Wall includes the native group and its fresh postprocessor. Total CPU uses controller plus waited-child user/system time for the entire group, including sampling and postprocessing; native CPU sums `/usr/bin/time` counters. Simultaneous RSS sums the union of owned descendant PIDs from one 100 ms process-table sample across active native VMs, then takes the maximum of that group peak and the separate postprocessor peak. It does not sum independent VM maxima. Shared resident pages can be counted multiple times, brief peaks can be missed, and ordinary OS accounting limits still apply.

Merge/report time includes compatibility validation, accepted raw-counter merging and rendering. It excludes the fresh postprocessor VM startup, reading captures, generating the plan, and independent fixture assertions; those are included in postprocess wall and total CPU. An incomplete rejection takes microseconds because no complete aggregate/report is constructed. Medians of separate columns need not add together. Three samples provide observed ranges, not a performance guarantee.

### fixture-small

Median [minimum, maximum] across three alternating trials.

| Layout | Complete | Wall s | Total CPU s | Simultaneous peak MiB |
| --- | --- | --- | --- | --- |
| single | 3/3 | 1.459 [1.455, 1.474] | 3.405 [3.356, 3.681] | 114.250 [105.500, 116.484] |
| sequential2 | 3/3 | 2.322 [2.277, 2.574] | 5.881 [5.851, 6.616] | 108.016 [106.344, 109.594] |
| concurrent2 | 3/3 | 1.464 [1.336, 1.600] | 5.708 [5.234, 6.057] | 221.859 [200.016, 222.406] |
| sequential4 | 3/3 | 3.876 [3.747, 3.879] | 9.700 [9.626, 11.089] | 105.156 [101.047, 109.875] |
| concurrent4 | 3/3 | 1.476 [1.475, 1.736] | 9.111 [8.683, 9.321] | 413.531 [409.609, 418.656] |

Median phase/work costs (s except the final column). Preparation is the sum across VMs, so concurrent spans can overlap.

| Layout | Native wall | Native CPU | Summed preparation | Postprocess wall | Merge/report ms |
| --- | --- | --- | --- | --- | --- |
| single | 0.811 | 1.960 | 0.069 | 0.652 | 8.289 |
| sequential2 | 1.753 | 4.190 | 0.132 | 0.640 | 8.944 |
| concurrent2 | 0.811 | 4.310 | 0.148 | 0.655 | 8.747 |
| sequential4 | 3.222 | 7.640 | 0.251 | 0.651 | 10.271 |
| concurrent4 | 0.955 | 7.610 | 0.371 | 0.523 | 10.097 |

### fixture-burst

Median [minimum, maximum] across three alternating trials.

| Layout | Complete | Wall s | Total CPU s | Simultaneous peak MiB |
| --- | --- | --- | --- | --- |
| single | 0/3 | 1.465 [1.328, 1.616] | 3.978 [3.464, 4.021] | 116.250 [103.344, 122.266] |
| sequential2 | 0/3 | 2.284 [2.146, 2.402] | 6.116 [5.834, 6.152] | 113.219 [105.844, 114.312] |
| concurrent2 | 0/3 | 1.473 [1.466, 1.760] | 5.625 [5.375, 5.698] | 224.344 [223.219, 230.859] |
| sequential4 | 3/3 | 4.640 [4.013, 4.715] | 10.960 [10.885, 11.600] | 108.984 [105.500, 109.672] |
| concurrent4 | 3/3 | 1.871 [1.749, 2.920] | 9.234 [9.158, 10.870] | 422.500 [410.641, 429.531] |

Median phase/work costs (s except the final column). Preparation is the sum across VMs, so concurrent spans can overlap.

| Layout | Native wall | Native CPU | Summed preparation | Postprocess wall | Merge/report ms |
| --- | --- | --- | --- | --- | --- |
| single | 0.807 | 2.320 | 0.078 | 0.657 | 0.006 |
| sequential2 | 1.625 | 4.300 | 0.149 | 0.654 | 0.006 |
| concurrent2 | 0.823 | 4.040 | 0.183 | 0.653 | 0.007 |
| sequential4 | 3.647 | 8.640 | 0.280 | 0.649 | 10.617 |
| concurrent4 | 1.217 | 7.410 | 0.502 | 0.655 | 10.730 |

### ecto

Median [minimum, maximum] across three alternating trials.

| Layout | Complete | Wall s | Total CPU s | Simultaneous peak MiB |
| --- | --- | --- | --- | --- |
| single | 0/3 | 10.278 [9.789, 15.119] | 36.450 [33.790, 42.501] | 674.922 [663.469, 690.422] |
| sequential2 | 0/3 | 17.109 [16.506, 21.263] | 52.574 [47.779, 59.221] | 636.078 [634.047, 742.234] |
| concurrent2 | 0/3 | 9.917 [9.720, 10.560] | 47.594 [45.728, 52.758] | 1252.875 [1247.500, 1254.188] |

Median phase/work costs (s except the final column). Preparation is the sum across VMs, so concurrent spans can overlap.

| Layout | Native wall | Native CPU | Summed preparation | Postprocess wall | Merge/report ms |
| --- | --- | --- | --- | --- | --- |
| single | 9.624 | 32.790 | 8.289 | 0.653 | 0.006 |
| sequential2 | 16.328 | 47.640 | 14.018 | 0.778 | 0.007 |
| concurrent2 | 9.138 | 44.240 | 15.775 | 0.778 | 0.007 |

### livebook

Median [minimum, maximum] across three alternating trials.

| Layout | Complete | Wall s | Total CPU s | Simultaneous peak MiB |
| --- | --- | --- | --- | --- |
| single | 0/3 | 24.056 [18.986, 27.314] | 69.799 [64.347, 70.409] | 941.797 [830.734, 980.750] |
| sequential2 | 0/3 | 35.124 [30.445, 38.680] | 98.533 [96.508, 98.884] | 917.312 [799.375, 935.906] |

Median phase/work costs (s except the final column). Preparation is the sum across VMs, so concurrent spans can overlap.

| Layout | Native wall | Native CPU | Summed preparation | Postprocess wall | Merge/report ms |
| --- | --- | --- | --- | --- | --- |
| single | 23.136 | 63.290 | 10.120 | 0.904 | 0.007 |
| sequential2 | 34.078 | 89.040 | 18.275 | 1.033 | 0.008 |

## Interpretation and retained limitations

All fifteen small groups completed, with one identical complete coverage hash and one report hash across layouts and trials. Sequential4's median sampled peak was about 9 MiB below single, but wall was about 2.7 times larger and ranges overlap. Concurrent4 used roughly 3.6 times the sampled median memory with essentially unchanged median wall. Duplicated preparation and VM startup dominate this small workload.

All fifteen native VMs belonging to the burst single/two-partition groups reported incomplete observation. All 24 native VMs in its four-partition groups were complete; their six aggregates had identical coverage/report hashes and passed the oracle. The partial single/two-partition elapsed values are retained for cost visibility only.

All Ecto and Livebook groups were rejected for trace-queue incompleteness despite passing their native suites. They cannot support a claim of faster complete observation. Ecto's first single trial had 12.898 seconds of preparation and 15.119 seconds end-to-end, without additional compile output; this slower first sample is retained. Livebook's observed native elapsed variability is also retained.

Every formal VM returned to the baseline trace-session inventory `[legacy: :default]`, with no surviving observer workers or shadow modules and no fallback stops. The separate `compiler_options_restored` audit was false in all three Livebook sequential2 partition-2 VMs and true elsewhere. The audit records equality, not the final differing key, so the exact option/cause cannot be recovered from these captures. Livebook contains its own compiler-option mutations, but that is not proof of attribution. Resource cleanup success must not be read as a claim that those options were restored.

The merger is a trusted, same-revision QA experiment for the two default checks, not a general library serialization contract or an untrusted artifact reader. Application-specific concurrent isolation, distributed execution, arbitrary file-internal partitioning, automatic partition selection, caching, and repeated-setup deduplication are outside scope.

## Acceptance, reviewer and reproduction

Six named empty acceptance tests first ran normally. Filling their bodies initially produced a missing-runner setup failure; this documents harness readiness, not six independent behavioral counterexamples. A first native attempt also failed because `--failures-manifest-path` is not a supported public CLI option. The correction configures the native ExUnit failures path before Mix starts, with one path and temporary directory per VM. It adds no Bylaw application configuration.

The runtime compatibility test then failed against a merger that accepted a changed runtime and passed after explicit runtime/schema validation. The independent reviewer reproduced a critical provenance defect: two unchanged invocations at the same path could share a trial/layout run ID and accept mixed partitions. Invocation UUIDs fixed it. Two new unchanged invocations with equal source fingerprints, distinct run IDs and independently valid original aggregates now reject the mixed pair. The failing and passing tests/logs are embedded in the results; initial reviewer setup errors are distinguished from the valid reproduction.

The six acceptance tests exercise ordinary single/sequential/concurrent partitions, exact counters/report equality, missing/duplicate/native failures, schema/code/runtime/options/target/inventory incompatibility, incomplete reason retention, unknown preservation, explicit repeated bootstrap calls and resource accounting. The reviewer separately checked all 45 groups, all 102 native VMs and all 45 postprocessors, including independent per-MFA checks for all 63 complete fixture VMs. No unresolved critical finding remained in that audit.

From `packages/bylaw_contract`, with the existing compatible dependencies and test BEAMs:

```sh
MIX_ENV=test mix compile
mix test test/partition_observation_acceptance_test.exs
python3 qa/run-partition-observation.py fixture /tmp/bylaw-partitions-small-new --trials 3 --iterations 10 --layouts single sequential2 concurrent2 sequential4 concurrent4
python3 qa/run-partition-observation.py fixture /tmp/bylaw-partitions-burst-new --trials 3 --iterations 300 --layouts single sequential2 concurrent2 sequential4 concurrent4
python3 qa/run-partition-observation.py ecto /tmp/bylaw-partitions-ecto-new --repo /tmp/bylaw-compiler-cap/ecto --trials 3 --layouts single sequential2 concurrent2
python3 qa/run-partition-observation.py livebook /tmp/bylaw-partitions-livebook-new --repo /tmp/bylaw-reasons.oRUJf0/livebook --trials 3 --layouts single sequential2
```

Use fresh output paths and the pinned external revisions. Run these serially; concurrent layouts only overlap their own native VMs. Re-evaluate a saved group with its recorded postprocessor command; raw input/plan/capture paths are in the artifact. Successful runner exit alone does not mean observation was complete.

The checked-in results retain all matrix rows/plans/audits, exact deduplicated inventories, log tails and hashes, raw ETF hashes, reviewer/acceptance evidence, and two representative complete merged ETFs encoded as zlib+base64. Decode the latter with Python `zlib.decompress(base64.b64decode(data))` and verify the recorded SHA-256 before reading the trusted ETF. Original raw files remain under `/tmp/bylaw-partitions-20260906`; hashed absolute paths identify this machine's measurements rather than portable checkout paths.

Root validation: `scripts/qa.sh` passed, including the six partition acceptance tests and all 974 UI tests. The review provenance regression is green. Raw validation output: `/tmp/bylaw-partitions-20260906/root-qa.log`.

The first pre-push gate later failed the existing ownership failure/timeout cleanup test (`test/ownership_probe_acceptance_test.exs:49`, seed 473717): it expected one failed child but observed four; 278/279 package tests passed. That outer log did not retain scenario identity or the child failure reasons, so the cause is unproven. The unchanged focused test passed with the same seed, and a separate unchanged timeout scenario produced exactly one intended timeout with clean trace resources. Both ownership files are unchanged in this PR. Their global 100 ms timeout is a possible scheduling sensitivity, not an established cause. The original failure and both repetitions are retained in the results artifact. Follow-up `bylaw-contract-diagnose-ownership-probe-failures` is deferred under `bylaw-quality`; no deadline or assertion was weakened here. Subsequent commit/push gate outcomes are reported in the PR.
