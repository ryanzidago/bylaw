# Repeated ExUnit contract sessions

Beads: `bylaw-contract-investigate-warm-exunit-sessions`, under `bylaw-performance`.

Loaded-module `ExUnit.run/1` is supported as a bounded, cheaper QA harness for
repeated contract sessions. The fixture preserves exact independent observations
and reports after failed tests and trace overflow, and releases all inspected
observer resources. This investigation does not establish a prepared-check cache
or justify a production performance change. Every repetition creates new check
workers and prepares checks again. No library code or default changes here.

## Reproduce and interpret

The measured library is Bylaw `e6695fd00fc889b44cdbc0d9cae88f50c77016ba`, following
baseline PR295, on Elixir 1.20.2 / OTP 29.0.3, ARM64 macOS with 14 schedulers.
The JSON evidence retains source hashes, exact commands, toolchain, external pins,
process IDs, results, report/coverage hashes and resource measurements. QA callback
annotations and an ignored helper return normalized to `:ok` were added afterwards;
the final acceptance run verifies that version. Production source is identical.

From `packages/bylaw_contract`, compile Bylaw's test build once, then choose a new
output directory per invocation:

```sh
MIX_ENV=test mise exec -- mix compile
mise exec -- python3 qa/run-warm-lifecycle.py /tmp/warm-complete
mise exec -- python3 qa/run-warm-lifecycle.py /tmp/warm-faults \
  --scenarios complete,failure,overflow,complete --mode defaults
mise exec -- python3 qa/run-warm-lifecycle.py /tmp/warm-scoped \
  --scenarios scoped,scoped,scoped --diff-base 728144ba
mise exec -- python3 qa/run-warm-lifecycle.py /tmp/warm-error \
  --scenarios scope_error,complete,complete
mise exec -- python3 qa/run-warm-lifecycle.py /tmp/warm-ecto \
  --repo "$ECTO" --tests test/ecto/uuid_test.exs
mise exec -- python3 qa/run-warm-lifecycle.py /tmp/warm-livebook \
  --repo "$LIVEBOOK" --tests test/livebook/runtime/erl_dist/node_manager_test.exs
```

Fault/error sequences intentionally exit 2; later success never clears them.
The default check pair is Typespec and FunctionClauses. `--mode` also supports
`typespec`, `structural`, `compiler`, and `all`. Compiler observation has no trace
queue, so its sequence is `complete,failure,complete`. Fault injection belongs to
the persisted generic fixture, not external application tests.

The Python wrapper rejects unapproved/dirty external revisions. Compilation is
outside the repeated-session timing and has its own 120-second bound. The measured
child has a 60-second deadline and 1536 MiB sampled process-tree RSS cutoff. Both
use owned process groups. These bounds are sampling controls, not hard memory
limits. Commands ran serially on a shared machine. Native `/usr/bin/time -l`
`reported_real_s` is the wall-time comparison; Python elapsed includes polling.

`warm-lifecycle.exs` uses `ExUnit.start(autorun: false)`, requires tests once, then
calls `ExUnit.run/1` with the loaded modules. It retains each result immediately.
Native test compiler defaults are applied, with the caller project's overrides
(Livebook `docs: true`), and restored afterwards. Requiring unchanged test modules
is not recompilation and cannot validate edited tests.

The diagnostic formatter proxy delegates real init, suite/test casts, finish and
terminate callbacks. An isolated trace session captures the return of the real
`Tracer.stop/1`; it does not manually finalize the formatter. A separate collector
receives that trace. The probe snapshots worker resources and serializes coverage,
so its timings and RSS include diagnostic overhead. Baseline unprofiled controls
remain in `performance-phases-2026-09-06.md`.

Initialization time includes capture setup and real formatter initialization;
stop time includes real finish/report printing and receiving the captured result.
Run time includes the full ExUnit session and capture file write. These are nested
intervals and must not be added together. A caller GC happens after a function
returns only a compact result row, excluding the captured coverage from its live
variables. `post_capture_gc_beam_bytes` is total VM memory at that point, including
loaded code, app state, retained hooks and compact prior result rows; it is not
prepared-state size, allocation volume or RSS. Other processes are not forced to
GC. Private `:elixir_config` hook inspection is read-only and version-specific.

## Lifecycle evidence

`warm-sessions-results.json` retains 22 final subprocesses and 86 sessions. Every
requested session executed, with one OS PID per multi-run command and fresh
observer/worker PIDs. Every inspected worker, tracer, queue-budget monitor,
diagnostic collector and trace session was released; generated shadow modules
were unloaded and all original application module MD5s remained unchanged.

Of 80 fixture sessions, 75 have complete observation and independently exact
counts: 20 Typespec calls/returns for each of 12 classifiers, 20 structural calls
for each of 24 functions, exact head/guard/selected outcomes for 48 clauses, and
20 compiler calls for each of its default ten observed choice functions. Complete
sessions have identical full-coverage/report hashes within each fixed-mode/scope
sequence. A failed assertion occurs after its workload and still preserves those
counts. Five test-failure sessions, four forced-overflow sessions and one scope
initialization error remain in the evidence. Overflow reports incomplete; its
partial counts are not compared as complete observations.

Twenty unscoped sessions retain zero formatter exit hooks. Twenty valid scoped
sessions retain hooks 1 through 20, each holding a successful completion value 0.
A scope-error session holds completion value 2; two later unscoped successes do
not clear that prior error, and the command exits 2. This supports failure
aggregation but does not establish bounded hook retention for an indefinitely
running scoped session. That separate hypothesis is deferred as
`bylaw-contract-investigate-warm-completion-hooks`.

Four normal acceptance tests cover repeated exact runs, failed-test recovery,
overflow recovery, and aggregation. The empty inventory ran before test bodies;
the initial red result was the absent new QA harness, not a production defect.
The completed tests pass against unchanged production behavior.

## Matched timing and memory controls

Each pair performs exactly 36 fixture tests: three sessions in one VM versus
three separate one-session VMs. Builds are warm on both sides. Pair order is
warm/fresh, fresh/warm, warm/fresh. The shared-VM process avoids two VM/app startups,
two diagnostic-module compilations and two test-module loads. These savings are
specific to this diagnostic command, not a Bylaw preparation optimization.

| Pair | Three sessions in one VM, s | Three fresh VMs summed, s |
| --- | ---: | ---: |
| 1 | 0.65 | 1.60 |
| 2 | 0.61 | 1.63 |
| 3 | 0.59 | 1.57 |

First-session default initialization is 35.2–36.4 ms in these warm commands;
subsequent preparation remains 23.3–28.7 ms. All nine fresh-VM initializations are
35.9–46.7 ms. Fresh checks become cheaper with loaded runtime/code, while their
state is recreated. There is no prepared-state reuse candidate in this task.

Twenty default sessions take 1.30 seconds total, with post-capture GC memory
52.10–54.98 MB (first 52.72, last 53.18). Twenty scoped sessions take 5.16 seconds,
53.94–55.64 MB (first 54.67, last 55.11). Scoped work also repeats source/diff
validation, so it is not a like-for-like preparation comparison. Sampled tree
peaks are 145.4 and 154.1 MiB respectively; paired short commands peak at
101.3–116.9 MiB. These short samples do not prove absence of a long-run leak.

## Preferred-repository QA

Retained compatible clean checkouts were used without source/test/dependency edits:
Ecto `11784f821a1bb0eedeee59583e311d836cb39ee1` and Livebook
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`. The selections exercise repeated native
runner lifecycle without assuming entire application suites are repeat-safe.
Historical Realtime/LiveView native toolchains remain outside current Bylaw's
Elixir requirement; no upgrade is attempted here.

| Default-check selection | Each of three runs | Whole command | Init, s | Post-capture GC memory, MB |
| --- | --- | ---: | --- | --- |
| Ecto UUID | 28 tests pass; observation incomplete | 14.08 s, exit 2 | 4.442 / 4.339 / 4.369 | 70.51 / 71.20 / 69.92 |
| Livebook NodeManager | 1 test passes; observation complete | 21.21 s, exit 0 | 6.079 / 5.831 / 5.912 | 99.37 / 102.35 / 99.71 |

All six sessions pass resource restoration checks. Ecto retains trace-overflow
reasons at the unchanged 4096 limit, so its timing is not complete-observation
throughput. Livebook full-coverage hashes vary despite complete transport; these
are observations of live application activity, not the deterministic fixture's
independent equality oracle. No claim of external exact-count equivalence follows.
Sampled tree peaks are 522.7 MiB for Ecto and 830.5 MiB for Livebook. No final run
hit its deadline or memory cutoff.

## Native semantics and limitations

Installed Elixir source was inspected directly: `ExUnit.run/1` documents loaded
module reuse; `maybe_repeated_run` restores modules within the running VM. A native
`mix test --repeat-until-failure 2` control executes three 12-test suites. Conversely,
two successive `Mix.Task.run("test", ...)` calls execute only one suite and return
`{:ok, :noop}`. Both control logs and commands are embedded in the JSON evidence.
The installed Mix test source at lines 584–590 calls `System.restart()` for
`--listen-on-stdin`; this is not an ordinary same-runtime-memory reuse contract.
No runtime-restart cache survival is inferred or measured.

Repeated tests may depend on application state or one-shot setup behavior, so this
bounded loaded-module harness is not a universal replacement for `mix test`.
Deferred prepared-check reuse remains deferred. No library defect or production
speedup was established. The added harness and evidence support future isolated
lifecycle/performance experiments with explicit caller-owned inputs.

Raw local experiments are under `/tmp/bylaw-warm-20260906`: the first self-tracer
pilot failed to capture its own return trace and is retained as a failed harness
experiment; a separate collector fixed it. Preliminary runs used memory samples
with the capture still live and are excluded from the final memory comparison.
`final/evidence.json` supplies the committed measurements; native controls are in
`final/native-evidence.json`. Independent reviewer scope-error recovery also passed
at `/tmp/bylaw-warm-review-scope-error-20260906/`.
