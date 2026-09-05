# Default-check memory investigation

Beads: `bylaw-contract-profile-large-project-preflight-memory`.
Library revision: `f8cb8ec6852e4e5b6a38cad7b3635ba4813829ed`.
Runtime: Elixir 1.20.2 / OTP 29.0.3 on macOS.

The confirmed residual problem is trace backlog: the default checks queue full
argument terms, and Typespec also queues payload-bearing returns. Suspending
consumers demonstrates approximately linear growth with queued payloads. Running
consumers can also fall behind the producer. This investigation does not claim
an uncontrolled OOM, a leak, or a universal memory bound. The implementation
follow-up is `bylaw-contract-bound-default-trace-backlog`; silently dropping
observations is not an acceptable fix.

All workloads here are generic persisted-BEAM fixtures. No external QA repository
or private application data is needed. The library runtime is unchanged.

## Bounded experiment

`memory-watchdog.py` samples the owned VM's macOS `proc_pid_rusage` physical
footprint every 20 ms and kills its owned process group when it exceeds 384 MiB
or runs for 60 seconds. The profiler independently samples BEAM total memory at
20 ms and phase boundaries, with a 384 MiB cutoff. These are sampled cutoffs,
not kernel-enforced maximum allocations; overshoot is possible. Physical
footprint and resident bytes are both recorded. A 1 MiB startup cutoff and a
100 MiB mid-workload cutoff terminated their owned VMs. The latter recorded
`incomplete_os_budget` at 137,839,288 sampled bytes and produced no final ETF.
The 384 MiB sleep control completed.

The original queue matrix contains 36 serial fresh-VM trials: four modes
(baseline, Typespec, FunctionClauses, default), three speeds and three repeats,
1,000 calls and 2,048 integers per payload. All completed with exact counts and
identical normalized coverage within each observed mode. Its maximum sampled
OS footprint was 153,502,416 bytes. Its `slow` case changes producer pacing too;
use the lifecycle matrix for independently controlled consumer slowdown.

A paused default trial measured 100, 500 and 1,000 queued messages per worker.
At 1,000 calls the two workers used 32,953,112 and 32,987,152 bytes; sampled
BEAM total was 116,631,125 bytes. Resuming and draining preserved all 1,000
Typespec calls and FunctionClauses callable-arity observations. An unsuspended
Typespec trial still queued 743 messages (24,707,912 worker bytes). A running
default trial queued 564 Typespec messages while its structural worker was
already caught up. These are measured snapshots, not queue maxima or throughput
benchmarks.

`memory-lifecycle.exs` separately samples fixture compilation, metadata loads,
direct check initialization, shadow compilation/cleanup, worker startup,
observation, stop/drain, summary, report generation, ETF encoding, per-cycle
cleanup and fixture cleanup. Startup includes initialization; direct init is a
separate control, not a subtracted estimate. Worker argument term sizes are
reconstructed from sequential direct-init claim results and measured separately; retained worker state is measured inside that worker to
avoid copying it back to the profiler.

The main matrix varies one axis at a time from one module, one function, alias
depth zero, 256 integers and one producer: modules 4/16, functions 4/16, alias
depth 4/12, payload 0/2,048, producers 2/4, and consumer speeds running/slow2/
slow10/paused. Slow consumers alternate 2 or 10 ms suspended with 2 ms active;
producer code is unchanged. All trials use 1,000 calls per cycle, three cycles,
three fresh-VM repeats and all four modes: 168 trials. The additional return
matrix uses 2,048 integers and returns `{:ok, payload}` against a two-alternative
spec, adding 48 trials across the four speeds and modes. This exercises actual
Typespec return observations instead of assuming every spec installs a return
trace. No combined maximum-axis stress or workload increase is used.

Successful trials assert exact per-function counts, 1,000 return events where
applicable, dead workers, ETF round-trip equality, and identical normalized
coverage/report hashes across cycles. The matrix verifier checks the complete
manifest's trial identities, configurations and cycle counts, and compares
reports across equivalent producer/speed variants. Baseline executes the same
fixture workload without Bylaw observers. Only owned temporary fixtures are
unloaded and removed. Final ETF output is written after fixture cleanup.

## Final matrix results

The reported matrices contain 216 successful fresh-VM trials and 648 cycles.
All manifest, exact-count, worker cleanup, ETF and equality assertions passed.
The main matrix compares 54 equivalent cycles per observed mode across base,
producer and speed variants; the return matrix compares 36 per observed mode.
The six allocator-control trials additionally passed equality across all 18
cycles, including across the cache setting change. All runs were serial.

| Matrix | Mode | Maximum sampled OS bytes | Maximum sampled BEAM bytes | BEAM peak phase |
| --- | --- | ---: | ---: | --- |
| Main | Baseline | 103,498,400 | 52,183,505 | Fixture cleanup |
| Main | Typespec | 181,256,888 | 78,099,290 | Observation |
| Main | FunctionClauses | 124,682,912 | 57,109,632 | Observation |
| Main | Default | 178,471,656 | 76,552,255 | Observation |
| Return payload | Baseline | 99,631,776 | 51,235,339 | Fixture cleanup |
| Return payload | Typespec | 216,302,312 | 117,653,932 | Stop/drain |
| Return payload | FunctionClauses | 190,530,280 | 85,668,908 | Observation |
| Return payload | Default | 277,054,232 | 152,922,265 | Stop/drain |

`default-check-memory-lifecycle.json` and `default-check-memory-returns.json`
retain per-case OS peak ranges, coverage/report hashes, ETF sizes, retained term
sizes and phase maxima with BEAM memory categories and peak timestamps. Cleanup
cycles remain separate in the phase summaries. Detailed logs and ETF captures
are intentionally kept outside the repository; the reproduction commands
regenerate them. The compact data summarizes repeats rather than preserving
large raw sample dumps.

On the base fixture, worker start arguments were 144 flat bytes per check.
Typespec retained state was 2,288 shared / 3,632 flat bytes and structural state
was 1,336 shared / 1,752 flat bytes. The default coverage ETF was 7,083 bytes.
The return fixture adds prior Typespec claims, making structural worker arguments
224 flat bytes. Those small-fixture values are not bounds for larger applications. Within this
bounded matrix, observation/drain dominated the measured BEAM peaks, so the
next implementation target is payload-bearing trace backlog. There is no
measurement here that justifies replacing metadata or coverage storage with
ETS, streams or persistent terms.

## Cleanup and runtime caches

The earlier return matrix showed cleanup BEAM memory near 53 MB while OS
footprint rose across repeated cycles. The eight measured allocators' used
blocks and carriers alone did not explain this difference. Erlang's segment
allocator also caches freed segments, so carrier totals are not a complete
account of retained runtime memory. See the [allocator documentation](https://www.erlang.org/docs/26/man/erts_alloc.html).

Six additional serial trials compared the same default/paused return workload
with default runtime settings and `+MMmcs 0`, three fresh VMs each. All completed
three cycles within the existing 384 MiB cutoff. With caching disabled, cleanup
footprint stayed between 75,498,120 and 86,885,024 bytes and cached-segment counts
were zero. Default settings retained 27–55 cached segments and cleanup footprint
ranged from 105,808,520 to 206,275,328 bytes. Detailed cycle measurements are in
`default-check-memory-cache.json`. This controlled comparison supports segment
caching as a contributor; it does not allocate every OS byte to a specific
runtime subsystem or establish a Bylaw leak. Disabling caching is an experiment,
not a recommended library configuration or a fix for unbounded queues.

## Interpretation limits

Phase peaks are sampled. OS phase attribution uses the nearest preceding BEAM
phase marker; short phases may have no OS sample. Simultaneously printed JSON
records and scheduler timing perturb these small workloads. Phase timings are
diagnostic, not a benchmark. Allocator blocks, carriers, BEAM memory and OS
footprint are different overlapping measures and must not be added together.
Term shared/flat byte sizes exclude some off-heap storage; binary/ETS/code
memory is separately sampled. `stored_nodes` traverses the stored terms,
including repeated references; it does not virtually expand named aliases.
Alias fixtures are linear chains, not exponentially branching definitions.
These measurements complement the existing compact-alias regression tests;
they do not replace their parser/expansion correctness coverage.

## Reproduction

Run from `packages/bylaw_contract` in the task worktree with the pinned runtime.
Use a new output directory; the matrix driver refuses to overwrite one. The
scripts read private check/worker state for diagnostics and are not public APIs.
Only decode ETF captures created by these local scripts.

```sh
profile_root=$(mktemp -d /tmp/bylaw-memory.XXXXXX)
mkdir "$profile_root/ebin"
mise exec -- elixir -e '
  [out] = System.argv()
  {:ok, _, _} = Kernel.ParallelCompiler.compile_to_path(
    Path.wildcard("lib/**/*.ex"), out, return_diagnostics: true)
' "$profile_root/ebin"
mise exec -- python3 qa/run-memory-lifecycle.py "$profile_root/ebin" "$profile_root/lifecycle"
mise exec -- elixir -pa "$profile_root/ebin" qa/compare-memory-lifecycle.exs "$profile_root/lifecycle"
python3 qa/summarize-memory-lifecycle.py "$profile_root/lifecycle" "$profile_root/lifecycle-summary.json"
mise exec -- python3 qa/run-memory-lifecycle.py "$profile_root/ebin" "$profile_root/returns" --returns
mise exec -- elixir -pa "$profile_root/ebin" qa/compare-memory-lifecycle.exs "$profile_root/returns"
python3 qa/summarize-memory-lifecycle.py "$profile_root/returns" "$profile_root/returns-summary.json"
```

To reproduce an allocator control, run this three times with distinct output
names, then repeat without `--erl '+MMmcs 0'`:

```sh
mise exec -- python3 qa/memory-watchdog.py "$profile_root/cache-off.os.json" 384 \
  elixir --erl '+MMmcs 0' -pa "$profile_root/ebin" qa/memory-lifecycle.exs \
  default paused 1 1 0 2048 1 1000 3 "$profile_root/cache-off.etf" return_payload \
  > "$profile_root/cache-off.jsonl"
```

For the original queue reproduction, use `qa/default-check-memory.exs` with
`default paused 1000 2048 OUTPUT.etf`, under the same watchdog. The initial
matrix's compact result file preserves its historical measurements; the final
lifecycle matrix supersedes its confounded producer-paced slowdown control.

## Validation and capture provenance

`scripts/qa.sh` passed, including all package format/compile/Credo/test/docs gates
and the UI checks. Diagnostic Elixir files also passed explicit format checks;
Python scripts passed syntax parsing. The report and data are an investigation,
not a production fix; no application compatibility rerun is attributed to this
PR because it does not change library code.

Session-local raw captures are under `/tmp/bylaw-memory-profile.5C0iQN`:
`lifecycle-final` supplies the main matrix, `returns-claims` supplies the return
matrix, and `cache-comparison` supplies the allocator control. The main matrix
predates the correction to account for nonempty return claims in startup
argument sizes; its fixture has no return alternatives and its claim sets are
empty. The affected return matrix was rerun after that measurement correction.
Earlier runs and the failed diagnostic accessor experiment are excluded from
the final matrix aggregates. That failed experiment exited as
`incomplete_process_exit`; it is not evidence of a production failure.
