# Current contract performance baseline

Beads: `bylaw-contract-rebaseline-performance-phases`, under `bylaw-performance`.
This investigation establishes a baseline for later performance decisions. Earlier
reports used older library revisions and sometimes incomplete observations.
The library's observation behavior, check defaults and 4096-message guard remain
unchanged. The changes here are QA capture, persisted fixtures and diagnostics.

## Reproduction and measurement contract

Run from `packages/bylaw_contract` in this task's dedicated worktree with
`mise exec --`. The measured library source is Bylaw `728144ba` (the branch's
library diff is empty), Elixir 1.20.2 and OTP 29.0.3 on ARM64 macOS, 14 schedulers.
The issue references 1.20.4 documentation; the installed 1.20.2 implementation
was inspected and tested directly. No toolchain upgrade is part of this work.

`run-performance-phases.py PROJECT CHECKOUT NEW_OUTPUT` records three alternating
orders of disabled, Typespec, FunctionClauses, combined defaults, compiler-only
and all three checks. Each trial uses a fresh VM, seed 922331, max_cases 4 and
normal concurrent Mix loading/execution. Scope and options stay fixed within a
comparison. `--fresh-build` creates a separate fixture build directory per trial;
the warm fixture matrix compiles before timing. External builds are already warm.
The entire command includes VM/app startup, preparation, tests and shutdown.

Each child has a 120-second deadline and a 1536 MiB sampled process-tree RSS
cutoff. `ps` samples simultaneous memory of the owned process tree about every
100 ms; shared pages can be counted more than once and short-lived peaks can be
missed. macOS `/usr/bin/time -l` supplies separate resource counters. Neither is
an allocation count or a hard memory guarantee. Python elapsed time also includes
polling/reaping delay; prefer the native `reported_real_s` value for short runs.
Heavy measurements run serially on a shared machine; three samples describe the
observed range, not a confidence interval or a promised speed ratio.

```sh
mise exec -- mix compile
MIX_ENV=test mise exec -- mix compile
mise exec -- python3 qa/run-performance-phases.py fixture \
  qa/performance_phase_fixture /tmp/bylaw-phase-cold --fresh-build
mise exec -- python3 qa/run-performance-phases.py fixture \
  qa/performance_phase_fixture /tmp/bylaw-phase-warm
mise exec -- python3 qa/run-performance-phases.py fixture \
  qa/performance_phase_fixture /tmp/bylaw-phase-diagnostic --diagnostic --trials 1
mise exec -- python3 qa/run-performance-phases.py livebook "$LIVEBOOK" \
  /tmp/bylaw-livebook-node --selection test/livebook/runtime/erl_dist/node_manager_test.exs
mise exec -- python3 qa/run-performance-phases.py ecto "$ECTO" \
  /tmp/bylaw-ecto-full --modes disabled defaults compiler
mise exec -- python3 qa/run-performance-phases.py livebook "$LIVEBOOK" \
  /tmp/bylaw-livebook-full --modes disabled defaults
mise exec -- python3 qa/run-performance-diagnostics.py \
  /tmp/bylaw-phase-native "$LIVEBOOK"
```

The runner rejects a wrong external revision, a dirty checkout, missing terminal
capture and wrong check set. Exit zero alone does not imply complete observation.
Raw ETFs retain the full coverage, failures, native timings and test times; JSON
retains a deterministic full-coverage SHA256 and explicit incomplete reasons.
The small fixture's exact counters are independently checked with
`verify-performance-fixture.exs CAPTURE...`; its public result assertions execute
in normal ExUnit. The specimen includes integer guards and deterministic atom
choices so compiler observation is exercised, including its default function cap.

## Compiler settings and overlapping intervals

Normal Mix 1.20.2 merges test options onto `docs: false`, `debug_info: false` and
`infer_signatures: false` before requiring tests and starting ExUnit, then restores
the options after awaiting the suite. Livebook explicitly overrides only
`docs: true`; its captures retain that override. The fixture and Ecto retain all
three false values. Inspected application modules are compiled separately with
their metadata intact. Repeated-session fixture loading applies the same test
options explicitly, restores them afterwards, and never recompiles the application
with test-only settings.

ExUnit's `load: nil` means loading and execution overlap. It is retained as null,
not converted to measured zero. Per-test times can overlap one another and do not
sum to suite wall time. Formatter initialization can overlap native test loading.
The diagnostic probe wraps selected library functions and the native Mix require
call in source compiled only in that diagnostic VM. It records absolute monotonic
start/end timestamps and PIDs without copying prepared metadata into a collector.
Nested spans are not exclusive intervals and must not be added together. Normal
paired timings use unmodified library BEAMs.

The phase categories are metadata extraction (`Specs.load`, `StructuralCoverage.load`,
`CompilerInference.load`), structural forms construction, classifier compilation,
check initialization, worker activation, native test loading, observation and stop.
Runtime-state construction is the residual of check initialization after its
nested load/shadow preparation, so it also includes normal callback bookkeeping.
Stop includes trace drain, coverage construction and cleanup; the structural
unload span is separately retained. ETF writing is outside the stop interval.

## Native tools and limits

`mix test --profile-require time` profiles test loading and does not run the tests.
It cannot be a successful suite baseline. `mix compile.elixir --force --profile time`
profiles application compilation, which is separate from Bylaw's Erlang classifier
compilation. `MIX_PROFILE=test` with tprof flags profiles task execution but is a
diagnostic run with profiler overhead; it does not directly provide the semantic
preparation/activation/drain boundaries. `ExUnit.Test.time` and the existing
`suite_finished` timing map are sufficient for test/suite timing and need no
second collector.

`performance-allocation.exs` uses tprof memory profiling with `warmup: false` and
`set_on_spawn: true`. It starts and stops the observer synchronously before the
profile ends, retaining per-process output so preparation workers and compiler
workers can be identified. Allocated words are not retained bytes or peak RSS.
The repeated-session diagnostic measures fresh check preparation each time;
loaded test-module reuse does not implement prepared-check caching.

`--slowest`/`--slowest-modules` enable diagnostic execution behavior and are not
used in normal matrices. `Code.purge_compiler_modules/0` concerns temporary
compiler modules on long-lived evaluating nodes and can terminate processes
executing their code. It is not used as a general memory optimization.

## Findings and adoption decision

Native ExUnit timings are useful and now survive the QA JSON export, including
null load times. Native tools alone do **not** separate Bylaw preparation,
activation and shutdown; bounded, separately labelled phase probes remain needed.
This is a supported measurement improvement, not a production speedup. No new
production optimization is justified within this baseline task. Existing deferred
preparation/cache/producer hypotheses remain deferred.

All 60 final fixture captures passed exact independent assertions and share one
full-coverage fingerprint per mode across cold builds, warm builds, diagnostic
instrumentation and three successive sessions. Each session runs all 12 tests.
Typespec records 20 calls and returns per classifier; structural coverage records
20 calls per sign/choice function and exact selection/head/guard outcomes.
Compiler-only and combined mode observe ten deterministic choice functions with
20 calls each, and retain the default-cap warning and unknown alternatives.
Transport completeness does not mean every inferred target is assessable.

| Mode | Fresh fixture build wall, median [range], s | Fresh VM/warm build wall, median [range], s | Warm-build init median, ms |
| --- | ---: | ---: | ---: |
| Disabled | 0.47 [0.46, 0.47] | 0.37 [0.37, 0.38] | 0.6 |
| Typespec | 0.47 [0.47, 0.48] | 0.40 [0.40, 0.41] | 27.5 |
| Structural | 0.48 [0.47, 0.49] | 0.40 [0.40, 0.41] | 49.0 |
| Defaults | 0.49 [0.48, 0.49] | 0.41 [0.40, 0.42] | 61.9 |
| Compiler | 0.48 [0.48, 0.50] | 0.42 [0.41, 0.43] | 35.3 |
| All | 0.51 [0.51, 0.52] | 0.44 [0.44, 0.47] | 76.8 |

The final fixture matrices have 36 unprofiled trials and six diagnostic trials.
Warm-build sampled tree peaks were 91.5–103.6 MiB by mode; cold-build maxima were
107.5–118.5 MiB. The diagnostic fixture wall times increased to 0.90–0.93 seconds
in enabled modes, roughly doubling the small normal run because diagnostic source
compilation is included. Its inner preparation timing is not a before/after
optimization comparison.

The 18 same-VM sessions use preloaded test modules and fresh check initialization.
Default preparation was 42.0/27.8/26.2 ms; structural 35.4/22.7/21.6 ms;
Typespec 16.5/5.0/5.3 ms; compiler 26.9/13.1/13.5 ms; all checks 71.7/41.6/39.9 ms.
Repeated-session timings exclude initial application startup and module loading,
so they cannot be compared directly with fresh-VM command wall time. Observed
BEAM memory after caller GC remained approximately 50.9–53.3 MB over these short
runs; this is neither a leak test nor proof that prepared metadata was reused.

## Preferred-repository evidence

Existing clean checkouts at the previously approved pins were used: Livebook
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716` and Ecto
`11784f821a1bb0eedeee59583e311d836cb39ee1`. No application source, tests, timeouts,
services or dependency declarations were edited. Historical Realtime and
LiveView native toolchains (Elixir 1.19.5 and 1.18.3 respectively) do not satisfy
current Bylaw's `~> 1.20` requirement; this task does not upgrade them. These
results are scoped to the two compatible retained checkouts, not every QA project.

| Livebook isolated NodeManager mode | Wall median [range], s | Init median, s | Maximum sampled tree MiB | Observation |
| --- | ---: | ---: | ---: | --- |
| Disabled | 0.87 [0.86, 0.89] | 0.001 | 197.2 | Disabled |
| Typespec | 1.63 [1.60, 1.73] | 0.733 | 249.8 | Complete |
| Structural | 6.74 [6.57, 7.00] | 5.842 | 831.6 | Complete |
| Defaults | 7.27 [7.15, 7.36] | 6.360 | 857.2 | Complete |
| Compiler | 1.46 [1.45, 1.47] | 0.566 | 238.5 | Complete |
| All | 7.78 [7.78, 7.84] | 6.845 | 851.9 | Complete |

All 18 isolated runs pass the selected test. Four additional phase diagnostics
also pass with complete observations. In the default diagnostic, structural
compilation is 4.027 seconds, structural metadata 0.538 seconds, typespec metadata
0.271 seconds, and two worker activations 0.249/1.113 seconds. Structural forms
construction is 4.2 ms and runtime-state/bookkeeping residual about 1.7 ms.
Stop is 23.1 ms, including two trace-stop spans of 5.4/5.9 ms and shadow cleanup
1.7 ms. The native require span is 30.6 ms and overlaps preparation; adding it to
all preparation spans would double count wall time. Compiler-only metadata is
0.210 seconds within a 0.360-second check initialization.

| Full-suite mode | Wall median [range], s | Test outcomes across three trials | Observation |
| --- | ---: | --- | --- |
| Ecto disabled | 2.42 [2.29, 3.29] | 1,591 passed each | Disabled |
| Ecto defaults | 6.09 [5.99, 8.07] | 1,591 passed each | Incomplete each |
| Ecto compiler | 2.27 [2.23, 5.14] | 1,591 passed each | Complete each |
| Livebook disabled | 13.55 [12.49, 15.06] | 1,511 passed twice; 1,510 passed/1 failed once; 185 excluded each | Disabled |
| Livebook defaults | 32.14 [18.41, 32.21] | 1,511 passed each; 185 excluded each | Incomplete each |

Every default full-suite capture retains queue-overflow reasons at the unchanged
4096 limit. They are not measurements of complete observation throughput. Full
Livebook initialization varied substantially while tests were loading concurrently
(median 16.519 seconds); the isolated measurements cannot be extrapolated into a
full-suite latency guarantee. Sampled tree maxima were 703.5 MiB for Ecto defaults
and 975.8 MiB for Livebook defaults. No final trial hit its external cutoff.

The disabled Livebook failure was `FileGuardTest` line 41: after the owner exited,
`lock` returned `{:error, :already_in_use}`. Bylaw modules were verified absent.
This proves occurrence without Bylaw, not the cause or universal independence
from observation. `bylaw-contract-qa-livebook-fileguard-timing` records the deferred
investigation. `bylaw-contract-investigate-trace-activation-cost` records the
separate deferred activation-cost hypothesis after duplicate searches.

## Allocation and native-tool results

The bounded memory profiles finish successfully and report distinct worker PIDs.
The fixture combined-default profile includes Typespec extraction, structural
preparation and a spawned Erlang compiler worker. The Livebook structural profile
also includes that compiler worker; the largest allocations occur in compilation.

| Allocation diagnostic | Reported allocated words, all profiled processes | Profiled processes |
| --- | ---: | ---: |
| Fixture Typespec | 100,829 | 4 |
| Fixture structural | 4,365,236 | 5 |
| Fixture defaults | 4,460,856 | 7 |
| Fixture compiler | 1,767,146 | 25 |
| Livebook Typespec | 26,199,794 | 4 |
| Livebook structural | 1,011,785,403 | 5 |

These are cumulative tprof allocations, not live/retained memory. The structural
Livebook total corresponds to roughly 8.09 GB of allocated words at eight bytes
per word over the run, while its sampled process-tree peak is separately bounded
and recorded. Per-process totals include functions below the display's 1000-word
filter; displayed rows therefore need not sum to the total.

Native `--profile-require time` reports a 51 ms fixture compilation cycle and no
ExUnit results, confirming tests were not run. Application compile profiling
reports a separate 26 ms compilation cycle plus callbacks. `MIX_PROFILE=test`
runs all 12 fixture tests and includes spawned compiler/test processes; its
per-function output is useful diagnostic evidence but does not replace the
semantic phase boundaries. All 15 native/repeated-session/profile commands exit
zero. Allocation profiles are paired with the unprofiled matrices above, not
used as speed measurements.

## Retained artifacts and validation

`performance-phases-results.json` retains per-trial commands, pins, source/BEAM
fingerprints where captured, process-tree resource samples, exact coverage hashes,
failures, incomplete reasons, native timing maps, test-time summaries, 18 warm
sessions, allocation process totals/function rows and diagnostic spans. Original
ETFs/logs/manifests remain under `/tmp/bylaw-performance-20260906`; they are
reproducible with the committed drivers. Full results are retained even when a
control fails. Per-mode coverage fingerprints match all 60 final fixture captures.

Exploratory captures remain separate: the initial generated-module fixture did
not exercise compiler instrumentation; authored integer guards remained ambiguous
for compiler clause attribution, so deterministic atom-choice functions were
added before the final matrix. A wrong Livebook test path produced 18 failed
pre-test commands and no terminal captures. Neither experiment is counted in the
final baseline or silently treated as passing QA.

Four new acceptance tests first ran as an empty inventory. Implemented bodies
reproduced three failures in the unchanged export: missing native timing data,
missing deterministic coverage fingerprint and unsupported combined-default mode.
After the QA changes all four pass, including rejection of a wrong check set.
The independent fixture oracle passes all 60 captures. Repository-wide `scripts/qa.sh` passed, including 974 UI tests with zero failures.
The final critical-only subagent review independently verified all 60 captures,
per-mode fingerprints, timing tables, overlapping spans, allocation totals and
compiler-worker scope. It reported no reproducible critical findings.

## References

- Installed Mix source: `lib/mix/lib/mix/compilers/test.ex` and `tasks/profile.tprof.ex`.
- [Mix test compiler at the issue's referenced version](https://github.com/elixir-lang/elixir/blob/v1.20.4/lib/mix/lib/mix/compilers/test.ex).
- [ExUnit formatter timing semantics](https://hexdocs.pm/ex_unit/1.20.2/ExUnit.Formatter.html#t:times_us/0).
- [Mix tprof options and asynchronous caveat](https://hexdocs.pm/mix/1.20.2/Mix.Tasks.Profile.Tprof.html).
- [Compiler-module purge scope](https://hexdocs.pm/elixir/1.20.2/Code.html#purge_compiler_modules/0).
