# Discard unused structural clause bodies

Structural preparation now discards original function bodies after extracting
clause metadata. Heads, guards, annotations, identifiers and reporting locations
remain unchanged. This resolves the demonstrated retention mechanism in
`bylaw-contract-investigate-retained-clause-bodies`; the classifier plan no longer
grows with an otherwise irrelevant literal body. The initial BEAM decode still
reads that body, and the plan is transient preparation data rather than the state
kept throughout observation.

## Boundary and preservation

The baseline is `d3c535ebe95f2dde7c9ae74ea18eadc55b256d4d`. The production change
only replaces the body in each retained Erlang clause tuple with `[]` at
`StructuralCoverage.extract_definition/5`. Subsequent code already replaces bodies
with generated classification outcomes. Only `StructuralCoverage.beam` differs
between the pinned baseline and measured candidate builds. Public APIs, compiler
options, targets, checks, observation boundary and the default 4096-event guard are
unchanged.

Three named empty acceptance tests ran normally. After implementing their bodies,
the unchanged baseline failed the two retention assertions and passed the
preservation assertion. An earlier fixture setup failure caused by disabled debug
information is retained separately and is not counted as valid regression evidence.
The candidate passes all three and 31 existing focused structural tests. The new
persisted fixture varies body size while keeping source lines, heads and guards
fixed, independently checks native arithmetic and side effects, checks the exact
locations and labels, exercises a caller-sensitive guard, verifies the shadow never
executes the original body, and verifies original module identity and cleanup.

An independent reviewer compared all 28 persisted package fixture/example modules
(92 clauses). Loaded metadata is identical after projecting only baseline bodies
to `[]`; generated shadow executable MD5s and original module identities match.
Absent and preloaded unsupported modules have unchanged outcomes. All 27 formal
preparation pairs also have exactly matching metadata, source identities, targets,
warnings and shadow executable MD5s. Every generic fixture passes its independent
native arithmetic and exact structural selection/head/guard oracle.

## Retained data and direct preparation

Three alternating baseline/candidate pairs per case run serially in fresh VMs on
Elixir 1.20.2 / OTP 29.0.3, ARM64 macOS, 14 schedulers. Fixtures are persisted and
compiled before timing. Body size and module count vary independently; every
fixture module has two clauses. All 54 planned direct commands pass, with unchanged
inputs, no resource cutoff and released shadows.

| Modules | Literal body entries | Baseline shared plan, bytes | Candidate shared plan, bytes |
| ---: | ---: | ---: | ---: |
| 1 | 8 | 2,000 | 1,024 |
| 1 | 64 | 6,032 | 1,024 |
| 1 | 512 | 38,288 | 1,024 |
| 1 | 4,096 | 296,336 | 1,024 |
| 4 | 512 | 152,864 | 3,808 |
| 16 | 512 | 611,168 | 14,944 |
| 64 | 512 | 2,444,384 | 59,488 |
| Ecto application | Existing bodies | 7,400,240 | 1,654,112 |
| Livebook application | Existing bodies | 53,669,944 | 2,864,080 |

Plan sizes are identical across repetitions. The one-module candidate is also
exactly 1,160 flat bytes at every body size. Livebook's shared plan decreases about
94.7%; Ecto's about 77.6%. `:erts_debug.size/1` measures shared reachable term words,
while `flat_size/1` counts duplicated occurrences. Neither includes all off-heap
payloads, generated code, allocator reservation or whole-process memory.

Median [minimum, maximum], milliseconds, with forced collections outside timers:

| Case | Variant | Metadata load | Shadow creation |
| --- | --- | ---: | ---: |
| 64 modules, 512 entries | Baseline | 18.291 [16.845, 20.775] | 65.753 [65.225, 71.627] |
| 64 modules, 512 entries | Candidate | 16.365 [16.155, 16.511] | 62.512 [62.371, 62.695] |
| Ecto | Baseline | 129.226 [128.842, 130.281] | 5,432.326 [5,417.098, 5,671.665] |
| Ecto | Candidate | 122.524 [119.867, 122.882] | 5,418.663 [5,406.715, 5,422.427] |
| Livebook | Baseline | 754.294 [740.259, 778.703] | 5,379.473 [5,357.878, 5,558.504] |
| Livebook | Candidate | 554.464 [548.035, 566.364] | 5,542.911 [5,435.076, 6,013.114] |

The large direct-command elapsed reduction is dominated by walking the retained
term for size inspection: Livebook's controller-elapsed median is 70.711 versus
9.071 seconds. It is
not a library speedup measurement. Those commands also force GC and compute
semantic hashes. Their OS peaks are diagnostic values, not native application
peaks. Small fixture load timings are noisy; the largest single-body candidate
even has a higher load median. The reliable result is removal of retained data,
not uniform acceleration of every phase.

The probe records BEAM total/process/binary/code/ETS memory before load, after a
post-load collection, after shadow creation and after releasing the plan. These
snapshots distinguish retained terms from VM allocation but are not phase peaks.
Separate instrumented runs wrap BEAM decoding, definition extraction, aggregate
loading, generated forms and compilation. Their spans are nested and inclusive;
they must not be summed as disjoint costs or mixed into uninstrumented timings.

After the post-load collection, median BEAM total memory is 123.5/74.5 MiB for
Livebook and 66.4/56.3 MiB for Ecto (baseline/candidate). After releasing the plan,
Livebook returns to essentially the same 68.7/68.8 MiB. Its code memory after
shadow creation is also essentially unchanged at 23.39 MiB. This supports removal
of transient metadata rather than reduced executable classifier state. Ecto's
direct-probe RSS and footprint medians actually increase, from 511.8/500.9 to
532.8/527.8 MiB, despite the smaller retained plan. Whole-process effects must be
measured separately.

All four nested phase diagnostic commands pass. The Livebook diagnostic records
710 BEAM chunk reads, 355 module loads and 3,695 definition extractions on each
side. Baseline/candidate inclusive chunk-read spans total 559.8/370.0 ms;
extraction totals 88.7/67.3 ms. Generated forms take 6.0/15.0 ms and compilation
5.428/5.414 seconds. These single instrumented samples do not prove phase speedups.
Two additional Livebook commands use the existing `structural-startup.exs` probe
with `ERL_COMPILER_OPTIONS='[time]'`, a 120-second deadline and 1,536 MiB sampled
RSS cutoff. Both pass. Shadow SSA optimization takes 3.206/3.121 seconds and its
reported intermediate size is identical at 44,013.3 kB. Strong/weak compiler
validators remain enabled. The diagnostic environment is absent from ordinary
measurements and production defaults.

## Native application measurements

Three alternating pairs run each application's full suite and the isolated
Livebook NodeManager test at `test/livebook/runtime/erl_dist/node_manager_test.exs:8`.
Both default checks prepare all application targets. Native test loading overlaps
preparation normally; seed 922331, max_cases 4 and native max_requires 14 remain
fixed. Temporary directories are distinct per command. Unlike the direct probe,
these native runs do not inspect retained term sizes or force diagnostic GC.

All 18 commands and offline decodes finish with exit 0, unchanged measured inputs,
no cutoff, no native test failures, and clean workers, shadows and owned trace
sessions. Ecto passes 1,591 tests; full Livebook passes 1,511 with its existing 185
exclusions. Every isolated run passes one test and observes completely. All full
Ecto and Livebook observations remain explicitly incomplete at the unchanged
trace-queue guard; their differing coverage hashes are retained. They cannot
establish equal complete-observation throughput.

An offline audit verifies identical sorted native test identities within each
workload, including exclusions, and identical full coverage and rendered-report
hashes across all six complete isolated runs. The initial auditor incorrectly
required an explicit `status` key on complete coverage; its retained error was
fixed to follow the existing complete-by-default representation. Native captures
were not rerun or changed. Isolated NodeManager audits retain the known
`compiler_options_restored: false` result caused by its live runtime setting
`ignore_module_conflict`; the earlier disabled-observer control in
`preparation-overlap-2026-09-06.md` documents that behavior. All full-suite audits
restore compiler options.

Median [minimum, maximum] over three runs:

| Workload | Variant | Native wall, s | Total CPU, s | Sampled tree RSS, MiB | Sampled tree footprint, MiB |
| --- | --- | ---: | ---: | ---: | ---: |
| Ecto full | Baseline | 8.38 [8.37, 8.86] | 31.96 [30.18, 32.69] | 797.83 [636.98, 804.86] | 751.03 [639.97, 754.50] |
| Ecto full | Candidate | 8.63 [8.46, 8.64] | 33.48 [30.36, 34.62] | 660.77 [659.50, 665.38] | 649.94 [603.50, 654.42] |
| Livebook NodeManager | Baseline | 10.44 [10.29, 10.98] | 24.68 [21.80, 28.14] | 862.53 [744.05, 865.39] | 802.96 [719.32, 860.14] |
| Livebook NodeManager | Candidate | 10.07 [10.03, 10.29] | 25.62 [24.05, 26.82] | 653.08 [649.23, 718.27] | 630.16 [629.46, 645.60] |
| Livebook full | Baseline | 17.80 [17.66, 18.04] | 58.33 [56.12, 59.26] | 968.19 [964.36, 984.80] | 946.82 [933.92, 960.05] |
| Livebook full | Candidate | 16.99 [16.88, 17.40] | 58.26 [54.84, 60.29] | 768.64 [764.02, 858.61] | 750.02 [728.57, 865.86] |

These native medians support reduced peak process memory in the measured workloads:
RSS decreases about 17% for Ecto, 24% for isolated Livebook and 21% for full
Livebook. Individual Ecto ranges overlap and not every pair improves. Footprint
medians also decrease. Three repetitions do not establish a hard ceiling or a
precise small speed difference. Ecto's wall median increases about 3%; Livebook's
decreases about 4% in the isolated selection and 5% in the full suite. The full
suite's incomplete observations further limit speed interpretation.

Initialization medians are baseline/candidate 7.321/7.506 seconds for Ecto,
8.257/7.866 for isolated Livebook, and 9.603/9.101 for full Livebook. Native stop
medians are 7.486/7.932, 29.469/24.955 and 51.468/14.881 milliseconds respectively.
The incomplete full-suite stop comparisons do not prove faster draining of the
same trace stream. Native wall and CPU come from `/usr/bin/time` and include
bootstrap and teardown; controller elapsed includes sampling/polling separately.

The hypothesis is supported for unnecessary retained data and partially supported
for broader performance: measured native memory improves, while speed changes are
small and mixed. The small extraction change is justified without adding a new
preparation lifecycle or reducing structural semantics.

## Reproduction and retained evidence

Use dedicated, clean Ecto and Livebook checkouts pinned respectively to
`11784f821a1bb0eedeee59583e311d836cb39ee1` and
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`. This investigation uses owned clones
under `/tmp/bylaw-retained-20260906`, with warmed build directories and no external
source, configuration or test edits. Preferred Realtime and LiveView pins remain
excluded for their previously established runtime incompatibility; no upgrades
or shims are introduced.

From `packages/bylaw_contract`, build and copy a baseline test ebin before applying
the patch, retain its `structural_coverage.ex`, then compile the candidate:

```sh
MIX_ENV=test mise exec -- mix compile
mise exec -- elixir qa/retained-body-fixtures.exs /tmp/retained-fixtures
mise exec -- python3 qa/run-retained-bodies.py prepare /tmp/baseline-ebin _build/test/lib/bylaw_contract/ebin /tmp/retained-fixtures /tmp/retained-prepare --ecto /tmp/pinned-ecto --livebook /tmp/pinned-livebook --baseline-source /tmp/baseline-structural-coverage.ex --trials 3
mise exec -- python3 qa/run-retained-bodies.py native /tmp/baseline-ebin _build/test/lib/bylaw_contract/ebin /tmp/retained-fixtures /tmp/retained-native --ecto /tmp/pinned-ecto --livebook /tmp/pinned-livebook --baseline-source /tmp/baseline-structural-coverage.ex --trials 3
mise exec -- python3 qa/run-retained-bodies.py diagnostic /tmp/baseline-ebin _build/test/lib/bylaw_contract/ebin /tmp/retained-fixtures /tmp/retained-diagnostic --ecto /tmp/pinned-ecto --livebook /tmp/pinned-livebook --baseline-source /tmp/baseline-structural-coverage.ex --trials 1
```

Output paths must be fresh. Each command has a 120-second deadline and 1,536 MiB
limits for sampled process-tree RSS and macOS physical footprint. A single process
snapshot supplies the owned descendant union every 100 ms; RSS sums its resident
sets and footprint sums successful `proc_pid_rusage` queries. Shared pages may
count repeatedly, failed footprint queries are absent and brief peaks can be
missed. These are protective cutoffs and sampled measurements, not hard memory
bounds. Offline native capture decoding is excluded from native timing and peaks.

Raw manifests, exact commands, library/harness/BEAM/fixture hashes, logs, native
ETF captures, diagnostic spans, red/green evidence and reviewer scripts remain in
`/tmp/bylaw-retained-20260906`. `retained-bodies-results.json` retains the complete
formal manifests and rows, native inventories and output digests, diagnostic
spans, compiler logs, acceptance evidence, offline auditor and reviewer audit.
Repository-wide `scripts/qa.sh` passes with exit 0; its log and digest are retained.
The independent reviewer reports no critical findings.
