For the current decision, matched-scope results and acceptance evidence, read [ASSESSMENT.md](ASSESSMENT.md). The sections below retain development stages and their limitations.

# Producer-side observation prototype

This isolated experiment investigates `bylaw-contract-prototype-bounded-producer-observation`. Default contract tracing can overflow its unchanged 4,096-message queue during bursts; the measured baseline is in `../bounded-throughput-2026-09-05.md`. The experiment counts trace events directly in a native tracer callback without retaining argument terms or sending per-event messages. It produces standalone observation records. Bylaw.Contract continues to use its existing observer.

Run from `packages/bylaw_contract` using the installed Elixir/OTP toolchain and a C11 compiler:

```sh
mise exec -- python3 qa/producer-prototype/run.py /tmp/bylaw-producer-new-run
```

The output directory must be new. The runner retains compiler and test logs, treats compiler warnings as errors, and gives the test process a 35-second timeout. It builds outside the package and adds no native dependency to the Mix project. The macOS compiler invocation has been exercised; the Linux branch remains unverified.

## Development evidence

The initial eight standalone ExUnit tests passed on both Elixir 1.20.2 / OTP 29.0.3 and Elixir 1.19.5 / OTP 28.5.0.4:

- Eight concurrent producers each issue 8,192 calls with 4,096-byte binary payloads; call and normal-return counters are exactly 65,536 each.
- Fixture return, raise, throw and exit results match the unobserved baseline. The comparison now covers complete stack traces from matching fresh-process call sites.
- Two sessions independently count common events and can stop independently.
- Three repeated sessions preserve exact counts, invalidate their trace-session references after destruction and retain fixed counter storage size.
- A ceiling of three accepts exactly three events without reporting exhaustion, then saturates and reports incomplete on the fourth.
- A concurrent burst against a ceiling of 1,024 cannot wrap counts or clear incomplete status.

The tests began as runnable empty inventories. Initial transport bodies failed before the native module existed; two exhaustion tests failed before the additional API/handling existed. Raw initial logs are in `/tmp/bylaw-producer-prototype`. The C build initially exposed an ErlNifUInt64/platform uint64_t pointer-type mismatch; using the API's declared integer type fixed the warnings-as-errors failure.

The default native resource contains two event counters, eight classification counters, their ceiling and sticky incomplete reasons. An explicit allocation can reserve up to 64 classification counters. VM match specifications supply a tuple within the allocated counter capacity; malformed results set the flag. The production-sized experimental ceiling is UINT64_MAX. A smaller per-resource ceiling exists to exercise counter exhaustion; it does not change Bylaw's queue guard. This storage accounting excludes VM trace metadata, NIF resource overhead and transient arguments in the caller. Tests prove fixed payload size, not a hard process-memory bound or native-resource reclamation.

## Outstanding requirements

This is a raw transport experiment, not evidence of complete Typespec or FunctionClauses observation. The existing TypeMatcher traverses recursive type graphs and containers; structural matching executes generated Erlang classifiers. Their semantics have not been ported or connected to the native callback. Any design must preserve exact independent input, return and authored-clause outcomes, including caller-sensitive guards, without unbounded retained events or argument terms.

The later semantic tests below cover local recursion, function_clause failures, default wrappers and protocol dispatch. Additional shutdown races, selective module reload, reclamation timing without GC and general target-derived classification remain unresolved. The sampled workload measurements are not hard memory or latency guarantees. Focused approved external exercises are recorded below; full suites have not run for this prototype. No default library behavior has changed, and the issue remains open until its broader acceptance criteria are addressed.

OTP documents that tracer callbacks execute in the tracee's context and must be NIFs: [erl_tracer](https://www.erlang.org/doc/apps/erts/erl_tracer.html). This gives a transport path without rewriting observed modules; it does not by itself make the existing Erlang classifiers callable from that path.

## Classification and focused approved QA

VM-generated argument flags now retain overlapping integer/positive-integer outcomes, binary detection and caller-sensitive self equality. Malformed classification output explicitly marks the transport incomplete. These flags do not yet represent Bylaw target IDs, general authored-clause outcomes, or return alternatives. Absence of a match-spec result is valid for raw transport counting, so transport `complete` is not contract-coverage `complete`.

`external.exs` exercises explicitly supplied compiled modules from approved Ecto and Livebook checkouts. Both used Elixir 1.20.2 / OTP 29.0.3:

| Repository revision | Function | Cycles | Calls and returns per cycle | Expected argument flags per cycle |
| --- | --- | ---: | ---: | --- |
| Ecto `11784f821a1bb0eedeee59583e311d836cb39ee1` | `Ecto.UUID.cast/1` | 3 | 65,536 each | binary 49,152; atom 16,384 |
| Livebook `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | `Livebook.Text.Delta.Operation.from_compressed/1` | 3 | 65,536 each | binary 16,384; nonnegative integer 32,768; negative integer 16,384 |

Eight producers call four fixed inputs in each cycle. The exercises verify every returned value against independent expected values, exact counters and flags, unchanged module MD5 and destroyed trace-session references. The resource payload is 96 bytes on this machine, excluding VM/resource overhead. Observed timings are not overhead measurements: there are no paired timing controls. Full records are in `external-results.json`.

After building with `run.py`, run either focused exercise explicitly:

```sh
BYLAW_PRODUCER_NIF=/tmp/bylaw-producer-new-run/native mise exec -- elixir -r qa/producer-prototype/native.exs qa/producer-prototype/external.exs ecto /path/to/approved/ecto/_build/test/lib/ecto/ebin /tmp/ecto-producer-results.json
```

Use `livebook` and its approved compiled `ebin` path for the second exercise. The script does not discover other repositories or change upstream sources.

An initial full-stack comparison used successive elements of an outer Enum.map, whose recursive call frames differed between baseline and observed executions. Matching fresh-process entry points removed that harness difference; the full traces then matched. The failed run is retained at `/tmp/bylaw-producer-prototype/full-stack/tests.log`.

A direct VM probe rejected a match-spec attempt to invoke `apply/3` (`Function apply/3 does_not_exist`). Consequently, the existing Erlang TypeMatcher and generated classifiers cannot simply be called through that match-spec expression. This is a limitation of the proposed reuse path, not proof that a separate native classifier is impossible. A separate classifier would need equivalence tests for recursive containers, type graphs, guards and all existing supported semantics; primitive flags are insufficient evidence.

## Lifecycle regressions and current policy

The lifecycle stage had 13 runnable tests. The original OTP 29 run at `/tmp/bylaw-producer-prototype/reload-before/tests.log` passed 9/11 and exposed silent observation loss after reload, plus an unreliable global resource-count timing assertion. Both findings are retained rather than omitted from the evidence.

The isolated prototype now installs call probes on `erlang:finish_loading/1`, `erlang:load_module/2` and `erlang:delete_module/1` before enabling process tracing. Their native callback sets sticky incomplete status and does not add loader calls to target counters. This intentionally invalidates observation for any code-load/deletion attempt, including unrelated or unsuccessful ones; it is not a selective module-reload implementation. It does not wait for a sampled module hash to change, so the identical-bytecode atomic-load regression also invalidates observation. The tests cover compile/reload, identical-bytecode atomic loading and code deletion. Caller interference with tracing, NIF reload and every loader/runtime permutation remain outside the evidence.

Stopping during a deliberately suspended function passes unchanged: the old snapshot remains `{1, 0}` after resumption, and a new session receives neither its call nor its eventual return. This verifies the tested observation-window boundary, not every shutdown race.

The resource test now receives a destructor notification for each resource it creates, instead of requiring a global count to reach zero despite unrelated allocations. The notification is absent while the owner/session is live. After session destruction and owner exit, the test waits for release; if the one-second diagnostic window expires, it explicitly collects the isolated VM's traced-process heaps and requires release. Replaying seed 906547 demonstrated release after collection. This proves reclamation after references are collected, not deterministic reclamation within one second without GC. The runner supports `BYLAW_PRODUCER_SEED` to reproduce ordering. No production cleanup path forces global garbage collection.

The resource payload is now 112 bytes on the tested machine, including an optional release-notification PID and flag. The earlier 96-byte focused records remain in `external-results.json` with stage labels. The guarded Ecto and Livebook exercises were repeated: both still pass three cycles with exact flags/counts, unchanged results and module MD5. Resource overhead, traced-process heap references and VM tracing metadata remain outside this payload measurement.

These lifecycle changes leave general type/clause classification, return-alternative matching, additional semantic cases, and comparative memory/overhead analysis unresolved. The issue remains in progress and there is no default library integration.

## Bounded native list-rule experiment

`integer_list/1` constructs a resource with an explicit per-event traversal budget of 1–4,096 list cells. The callback classifies both the single argument and normal return as `list(integer())`, preserving arbitrary-size integer support without retaining values. A proper list at the exact budget can match; traversal beyond the budget sets incomplete and records no hit. Non-list, float-containing and improper-tail values do not match. This one rule is a feasibility experiment, not a general native type compiler or authored-clause classifier.

The current standalone suite has 16 tests. Its differential case compares 132 list shapes against the existing TypeMatcher. That comparison exposed a production improper-tail crash, fixed independently in [PR289](https://github.com/ryanzidago/bylaw/pull/289). After bringing merge `f1cdcd65574a88d4475070eaf5e69a03e25f61ec` into this worktree, all 16 tests passed on Elixir 1.20.2 / OTP 29.0.3 (seed 906547). Earlier 13-test runtime results do not claim coverage of these new cases.

## Workload comparison results

`list-workload.exs` and `workload-run.py` compare baseline, this native list rule and existing Typespec tracing in fresh VMs across 1/8 producers, 1,024/8,192 calls, lists of 16/256 integers and burst/paced execution. Pacing sleeps five milliseconds every eight calls per producer. The runner samples the owned VM's RSS every 100 ms, kills it above 384 MiB or after 35 seconds, and preserves failures. These are sampled safeguards, not hard byte-memory bounds. Interruption cleanup kills only the owned child process group.

After building the NIF and package test build:

```sh
BYLAW_PRODUCER_EBIN="$PWD/_build/test/lib/bylaw_contract/ebin" BYLAW_PRODUCER_NIF=/tmp/bylaw-producer-new-run/native mise exec -- python3 qa/producer-prototype/workload-run.py /tmp/bylaw-producer-workload-new
```

Comparisons must acknowledge unequal classification scope: native counts whole-list membership, while Typespec also emits empty/singleton/multiple input partitions and an unused return alternative. The harness checks all expected trace targets when complete; it does not claim general report equivalence or isolate transport cost from classifier work. Timing windows begin after setup, but peak RSS includes compilation and VM startup.

The first run `/tmp/bylaw-producer-workload` was deliberately stopped after assertions showed native zero-count observations. Its fixture was compiled to disk but not explicitly loaded before tracepoint installation. The corrected harness ensures the module is loaded and requires exactly one installed function tracepoint. The failed run is retained and excluded from valid comparison results; the corrected run uses `/tmp/bylaw-producer-workload-fixed`.


The corrected 48-trial run completed with no assertion failures or watchdog stops. All 16 native observations completed with exact call, return, input-match and return-match counts. Typespec tracing completed 12 cases and explicitly overflowed in all four 8,192-call bursts. The 16 baseline cases were unobserved. Full rows are retained in `workload-results.json`.

| Mode | Sampled peak RSS range (KiB) | 8,192-call burst producer time (microseconds) |
| --- | ---: | ---: |
| Baseline | 80,000–90,096 | 93–118 |
| Native integer-list rule | 82,048–91,824 | 5,183–33,404 |
| Typespec trace | 83,968–123,072 | 1,925–14,157 (all four incomplete) |

This demonstrates the cost of executing observation work in the producer: callers take substantially longer than the trivial unobserved echo function, while this restricted classifier completes the tested bursts. The shorter incomplete trace timings are not a completed-work comparison. There is only one run per configuration; these are exploratory measurements on a shared machine, not isolated performance guarantees. The standalone OTP28 regression suite ran briefly during paced configurations, another reason not to infer precise speed ratios from this series. No upper bound on total application memory follows from sampled RSS.

The 16-test standalone suite also passed on Elixir1.19.5/OTP28.5.0.4 against the corrected matcher source. That is an isolated experiment check; current Bylaw.Contract package support remains Elixir~>1.20.


## Semantic and structural-outcome validation

The current suite has 22 tests and passes on the tested OTP29 and OTP28 toolchains (seed917632). New characterization tests pass without transport changes for local tail recursion, captured local calls, default-argument wrappers and protocol implementation dispatch. Unmatched clauses preserve complete exception stack traces from identical fresh-process call sites and retain a call with no normal-return event.

An explicitly supplied VM match specification models two overlapping integer-guarded clauses. Its eight boolean outputs represent each clause's head match, guard pass, selection and guard rejection. Six stress configurations vary 16/4,096-bit integers, one/eight producers and burst/paced traffic. Each retains exactly8,192calls,6,144returns and counters `[8192,2048,2048,6144,8192,6144,4096,2048]`. This verifies transport of structural outcomes for the explicit model; it does not derive match specifications from arbitrary authored source or establish a general structural compiler.

The native status now retains atomic reason flags for counter exhaustion, invalid classification data, code changes and traversal-budget exhaustion. A test proves multiple causes survive together. The initial clause test retained exact counters but reported incomplete; the new reasons identified `code_change`. Running the unmatched-clause path in the unobserved baseline avoided that trigger while preserving the guard and exact counters. Failed runs are retained in `/tmp/bylaw-producer-prototype/{clause-outcomes,reasons-before,reasons-after}`; the passing full-baseline/stress runs are `semantic-baseline-complete` and `clause-stress`.

The approved focused Ecto and Livebook exercises were repeated after the reason-flag change, each passing three cycles with exact observations. Records are retained with stage `reason_flags`. Their timings ran alongside repository QA and must not be treated as performance comparisons.

Remaining work includes general bounded target/metadata translation, per-target mapping across larger target sets and integration with the existing checks. Explicit toy match specifications and one list rule do not satisfy those requirements. The task remains in progress; no default replacement is claimed.

Target metadata translation is isolated in `target-plan.exs`. From the package
folder, run its tests with:

```sh
mise exec -- mix run -r qa/producer-prototype/target-plan.exs qa/producer-prototype/target-plan-test.exs
```

The compiler assigns deterministic slots by target ID and emits explicit
module/function/arity, event, argument and classifier descriptors. It rejects
empty plans, more than eight targets, duplicate IDs, invalid argument positions
and unsupported types without dropping individual targets. Four tests cover
these decisions, including metadata loaded from a persisted typespec fixture
with three list input partitions and two return alternatives.

`ProducerNative.plan/2` now consumes the generated descriptors. It allocates a
fixed eight-rule program, retains only atom metadata and numeric fields, and
frees that program with the resource. The initial flat-rule payload was 456 bytes including
the program; the current tuple-capable fixed descriptor table uses 3984 bytes,
compared with 128 bytes for default raw counters on this platform. This
excludes allocator/VM overhead. Call parsing uses a fixed 255-term stack array;
list traversal shares a configurable 1..4096-cell budget across every matching
rule in one event. No arguments or event terms survive the callback. Exhaustion
marks the observation incomplete; earlier exact hits remain visible.

Two additional acceptance tests prove independent MFA/argument/return mapping,
overlapping slots, invalid native plan rejection and shared budget exhaustion.
All 24 tests pass with seeds 917632 and 516424. The initial inventory with seed
516424 failed an existing cleanup-owner readiness assertion at 100ms; the replay
passed without changing that assertion. Raw logs remain under
`/tmp/bylaw-producer-prototype/native-plan-{inventory,before,after,cleanup-replay}`.
Repository QA passed. Approved Ecto/Livebook raw-mode regression checks passed
three cycles each, retained as `native_plan_raw_regression`; those checks do not
exercise generated plans or prove full application contract coverage.

The supported primitive/list subset is not a general type or authored-clause
implementation. Native rule tests and persisted metadata translation tests are
now complemented by end-to-end persisted-metadata native observations below.
Broader type support and general authored-clause translation remain unfinished.


The `metadata-native-test.exs` test compiles a fixture, loads its persisted typespec
metadata and runs the generated native plan across eight shapes: 1/8 producers,
16/256 big-integer list elements and burst/paced traffic. Each shape observes
8192 exact calls/returns and all five target IDs agree with TypeMatcher, including
the selected literal-atom return alternative. The independently expected hit
multiset is four counts of 2048 and one of 6144. Raw output is retained at
`/tmp/bylaw-producer-prototype/metadata-native.log`.

`clause-plan.exs` translates actual StructuralCoverage classifier metadata for a
restricted subset: at most sixteen clauses, eight arguments, variable, atom-literal and small-integer-literal heads,
primitive type predicates and comparisons of variables with small integer
constants. It bounds metadata traversal to 256 nodes per clause (including Erlang
annotations), rejects unsupported heads/guards and emits head, guard, selected
and rejected slots keyed by original clause IDs. It does not retain argument
terms. Tests compare a compiled overlapping-clause fixture with the existing
shadow classifier, then verify native counts `[4,1,1,3,4,3,2,1]` and unchanged
results. Unsupported `length/1`, tuple heads and oversized metadata are
explicitly rejected. This is not general source-pattern/guard coverage. The
first metadata cap of 64 was too small for the annotated fixture; its rejection
is preserved in `clause-plan-after.log`, followed by the passing corrected run
`clause-plan-after-fixed.log`. The fixed metadata limit is independent of the
unchanged trace queue limit.

Run these integration tests from the package directory after building the NIF
with `run.py`, substituting its actual output path:

```sh
BYLAW_PRODUCER_NIF=/path/to/build/native mise exec -- mix run -r qa/producer-prototype/native.exs -r qa/producer-prototype/target-plan.exs qa/producer-prototype/metadata-native-test.exs
BYLAW_PRODUCER_NIF=/path/to/build/native mise exec -- mix run -r qa/producer-prototype/native.exs -r qa/producer-prototype/clause-plan.exs qa/producer-prototype/clause-plan-test.exs
```


Clause translation now sorts and validates original clause positions before
constructing first-match selection expressions. Literal atom and small-integer
heads distinguish head misses, guard passes and selection; integer heads use
exact equality, so `7.0` does not match `7`. Repeated named variables and container
heads remain unsupported. The generated plan, rather than manually supplied
flags, passed six stress configurations (16/4096-bit integers; one burst producer,
eight burst producers and eight paced producers), each with 8192 calls, 6144
returns and exact outcome counts `[8192,2048,2048,6144,8192,6144,4096,2048]`.
Raw results: `clause-plan-generated-stress.log`; literal-head rejection before
implementation is preserved in `clause-literal-before.log` and the passing run
in `clause-literal-after.log` under `/tmp/bylaw-producer-prototype`.

Approved repository metadata inspection is retained in
`external-metadata-results.json`, generated by `external-metadata.exs` with the
same clean Ecto and Livebook revisions as the runtime exercises. Ecto.UUID.cast/1
has five typespec targets and three authored clauses; Livebook's
from_compressed/1 has six targets and three clauses. Both metadata loaders report
no warnings, but this prototype rejects a return-alternative type in each target
plan and, at that historical stage, rejected both clause plans at the two-clause capacity. No observation
was started in these metadata checks. They are explicit current coverage limits,
not successful generated-plan observations and not proof that expanding the
bounded interpreter is impossible. Prior raw-mode runtime checks remain separate.


Explicit native counter allocation now supports 8..64 slots via `new_slots/1`.
The default allocation remains eight slots and 128 payload bytes. Additional
counters occupy the resource's trailing storage, eight bytes per counter, and
are reclaimed with that resource. The measured 12-slot payload is 160 bytes;
the 64-slot payload is 576 bytes. Tests reject invalid capacities and verify
8192 concurrent calls/returns at 8, 12 and 64 slots with distinct true/false flags.
All 25 native acceptance tests pass (seed917632, `counter-slots-after`). Failed
pre-implementation evidence is retained in `counter-slots-before`.

Clause plans now return `slot_count` explicitly, bounded to 64 counters for 16
clauses. Callers allocate that capacity before installing the plan. The compiler
still bounds each clause's metadata traversal and rejects unsupported patterns
and guards. Its match-spec metadata is separate from the native resource payload;
reported payload bytes do not measure VM-compiled trace-pattern storage.

`external-clauses.exs` loads actual approved repository clause metadata, generates
a plan, obtains an independent per-input baseline from StructuralCoverage's
shadow classifier, and checks observed outcomes against that baseline. Retained
`external-clause-results.json` contains three successful Livebook cycles, each
65536 calls and returns across eight producers, with all 12 outcome counters exact,
unchanged results and module MD5. Ecto.UUID.cast/1 now rejects unsupported clause
patterns rather than capacity and does not start an observation. This is focused
authored-clause coverage for Livebook, not typespec coverage or a full application
suite. Neither repository's unsupported return-alternative types are resolved by
the counter-allocation change. No trace queue limit was changed.


The target compiler and native interpreter now support bounded nested tuples,
small descriptor graphs resolved from existing type aliases, and positive,
negative and non-negative integer classes, including arbitrary-size integers.
Aliases marked unsupported by Bylaw remain unsupported. Native metadata has a
fixed 64-node table shared by at most eight rules; tuple width and depth are each
limited to eight. The Elixir compiler rejects plans exceeding that shared node
capacity. Recursive aliases, excessive graph traversal, overly deep/wide tuples
and unsupported types are rejected before observation. Each native descriptor
visit and list-cell inspection consumes the shared event budget; exhaustion
retains the incomplete reason rather than treating an uninspected value as a hit.
No event terms are retained. The fixed plan payload is 3984 bytes, excluding VM
and allocator overhead, with a bounded parser/runtime stack and the existing
255-element argument stack array. This increases metadata storage explicitly; it
does not change the trace queue guard or the 4096 event-work budget ceiling.

Seven target-plan tests cover tuple aliases, sign classes and shared descriptor
capacity. Native tests cover nested tuple hits/misses, wrong arities, floats,
arbitrary-size integers, exactly 64 descriptor nodes and explicit capacity
rejection. Pre-implementation failures are retained in `tuple-plan-before.log`,
`tuple-native-before` and `tuple-node-capacity-before.log` under
`/tmp/bylaw-producer-prototype`. The eight-shape persisted-metadata workload
continues to pass against the tuple-capable NIF.

`external-targets.exs` now runs generated input/return plans from actual approved
metadata, with per-target expected counts from TypeMatcher and exact known
results. `external-target-results.json` retains three successful Livebook cycles,
each with 65536 calls/returns and all six target counts exact:
`[16384,32768,16384,16384,32768,16384]`. Results and module MD5 are unchanged.
Those typespec observations were separate from the authored-clause observations;
the later combined-session exercise is documented below. Ecto's own metadata
loader marks several UUID targets unsupported, so its generated target plan still
rejects explicitly. This change does not claim complete Ecto contract coverage.


`plan/3` explicitly reserves clause-flag counters after the target-rule counters.
The sum remains capped at 64. Each call executes native target classification and
validates the exact expected clause-flag tuple before incrementing its separate
slots. Calls and returns are counted once. Missing or malformed required flags
mark the observation incomplete; target hits already established remain visible.
The original `plan/2` and raw counter modes remain available. Two additional
inventory/body tests prove combined slot mapping, missing-flag handling and total
capacity rejection; all 28 native tests pass (seed917632, `combined-after`).
Failures before implementation are retained in `combined-before`.

`external-combined.exs` generates both plans from the same selected MFA's existing
Specs and StructuralCoverage metadata, uses TypeMatcher and shadow-classifier
baselines, then observes both in one native resource/session. Retained
`external-combined-results.json` contains three complete Livebook cycles, each
65536 calls/returns, six type-target counters and twelve clause counters exact,
unchanged results and module MD5. Native payload is 4064 bytes for this 18-counter
combined plan. Ecto's combined plan rejects unsupported loader metadata before
starting any observation. This remains focused function QA; full application
coverage and a general replacement for the production observer are not claimed.


## Reproduce the current comparison

From `packages/bylaw_contract`, compile the package and build the isolated NIF
into a new output directory. Use fresh output paths for subsequent runs:

```sh
mise exec -- mix compile
mise exec -- python3 qa/producer-prototype/run.py /tmp/bylaw-producer-run
export BYLAW_PRODUCER_NIF=/tmp/bylaw-producer-run/native
mise exec -- mix run -r qa/producer-prototype/target-plan.exs qa/producer-prototype/target-plan-test.exs
mise exec -- mix run -r qa/producer-prototype/native.exs -r qa/producer-prototype/clause-plan.exs qa/producer-prototype/clause-plan-test.exs
mise exec -- mix run -r qa/producer-prototype/native.exs -r qa/producer-prototype/target-plan.exs qa/producer-prototype/metadata-native-test.exs
export BYLAW_PRODUCER_EBIN="$PWD/_build/dev/lib/bylaw_contract/ebin"
mise exec -- python3 qa/producer-prototype/combined-workload-run.py /tmp/bylaw-combined-run
```

The final command performs the 48 fresh-VM matched-scope trials. It preserves
all results, including explicit incompleteness, under the supplied output path.
For approved external QA, `external-combined.exs` accepts the project name
(`ecto` or `livebook`), that approved checkout's compiled ebin directory, and an
output JSON path; load `native.exs`, `target-plan.exs` and `clause-plan.exs` first.
Do not substitute an unapproved repository.
