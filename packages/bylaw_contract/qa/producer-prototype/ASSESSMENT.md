# Bounded producer observation assessment

This experiment demonstrates exact producer-side type-target and authored-clause
observation for a bounded, explicitly supported subset without a per-event trace
mailbox. Keep it as an opt-in QA experiment. Do not replace Bylaw's default
observer with this implementation: unsupported types/patterns still reject real
Ecto metadata, code changes conservatively invalidate observations, and moving
classification into callers has a measurable cost. No production API, dependency,
queue limit or upstream application test was changed.

The task is `bylaw-contract-prototype-bounded-producer-observation`. The existing
4096-message observer guard remains necessary. This prototype does not make
current full-application contract observations complete.

The combined comparison uses one compiled function with the same five Typespec
targets and four authored-clause outcome counters in both observers. It runs
48 fresh VMs: baseline/native/trace, 1024/8192 calls, 16/256 integer list elements,
1/8 producers and burst/paced traffic. The native plan is generated from Specs
and StructuralCoverage metadata; the trace mode uses both existing checks.
Every complete trial asserts exact call, return and all classification counts.
The runner retains incomplete counts and failures, samples RSS at 100ms, and
limits its owned process to 35 seconds and sampled 384MiB RSS.

| Mode | Trials | Complete | Incomplete | Sampled peak RSS range, KiB |
| --- | ---: | ---: | ---: | ---: |
| Baseline | 16 | Not observed | Not observed | 84272–105392 |
| Native combined | 16 | 16 | 0 | 94768–103392 |
| Existing combined checks | 16 | 12 | 4 | 94128–106976 |

All four incomplete trace trials were 8192-call bursts. Every one retained an
explicit queue-overflow reason at the unchanged 4096 guard. All twelve complete
native/trace pairs had identical nine-counter results. There were no watchdog or
assertion failures. These outcomes agree with the earlier retained throughput
investigations while using matching classification scope, unlike the earlier
list-membership-only native comparison.

| Burst case | Baseline producer μs | Native producer μs | Native through stop μs | Trace producer μs | Trace through stop μs | Trace status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| 1024 calls, 16 elements, 1 producer | 16 | 1294 | 3260 | 906 | 8976 | Complete |
| 1024 calls, 256 elements, 1 producer | 14 | 5779 | 7378 | 3714 | 25839 | Complete |
| 8192 calls, 16 elements, 1 producer | 97 | 10781 | 12347 | 4074 | 9392 | Incomplete |
| 8192 calls, 256 elements, 1 producer | 83 | 46780 | 48348 | 15147 | 21041 | Incomplete |

Native classification shifts cost into the producer. For the single-producer
8192-call samples that is about 1.3μs/call at 16 elements and 5.7μs/call at 256
elements, substantially above the bare fixture. Faster incomplete trace times
are not completed-work speedups. There is one sample per setting on a shared
machine; startup/compilation contribute to RSS, and setup is excluded from
producer time. No stable speed ratio, application latency guarantee or hard
process-memory bound follows from these samples. The driver ran serially; no
other QA suite was launched by this session during the comparison.

`combined-workload-results.json` retains all 48 rows, including incomplete data.
`combined-workload-manifest.json` pins source hashes, ARM64, Elixir 1.20.2,
OTP 29.0.3 and Bylaw base f1cdcd65574a88d4475070eaf5e69a03e25f61ec. Raw logs are
in `/tmp/bylaw-combined-workload`. Clang's static analyzer reported zero
diagnostics for the native source; that is supplementary evidence, not proof
of native memory safety.

| Requirement | Evidence and limit |
| --- | --- |
| Exact calls, returns and classification | 28 standalone native acceptance tests; seven target-plan tests; four clause-plan tests; persisted metadata integration; matched-scope matrix above |
| Payloads, concurrency, pacing and repeated sessions | List-size matrix, six generated clause stress configurations with 16/4096-bit integers, repeated raw and combined external cycles |
| Return/raise/throw/exit and full stack behavior | Fresh-process baseline comparisons and function_clause regressions in acceptance.exs; no target compiler rewriting |
| Local recursion, captures, defaults and protocols | Dedicated semantic fixture tests assert exact totals and unchanged results |
| Concurrent sessions and shutdown | Separate-session counting and active-call stop tests; later sessions do not receive earlier calls/returns |
| Resource reclamation | Resource-specific destructor notification after owner/session exit; collection may be required; no immediate-release guarantee |
| Reload and restoration | Reload, identical-bytecode atomic reload and deletion mark incomplete; trace-session destruction removes installed trace settings |
| Exhaustion/unsupported inputs | Saturating atomic counters; sticky independent incomplete reasons; missing required flags fail explicitly; type, node, depth and slot capacities reject before observation |
| Approved repository comparison | Exact focused Ecto raw observations; generated Livebook types, clauses and combined observations; Ecto generated plans explicitly rejected rather than silently narrowed |

The supported native target vocabulary is primitive integers/atoms/binaries,
integer sign classes, literal atoms, integer-list membership/length partitions,
and bounded tuples/alias resolution. It is not the full TypeMatcher language.
Clause translation supports bounded primitive guards and variable, atom-literal
and small-integer-literal heads; container/binary patterns, repeated named
variables and general guards remain unsupported. Metadata is taken from existing
Bylaw loaders, not hand-written per-application rules.

The native resource holds 8..64 atomic hit counters, a call/return counter pair
and incomplete reasons. Default raw payload is 128 bytes; 12 counters use 160
bytes. A target plan adds a fixed 64-node descriptor table, with at most eight
target rules and tuple width/depth at most eight. A default target plan occupies
3984 bytes; Livebook's combined six targets plus twelve clause counters occupies
4064 bytes. Program metadata retains only atom references and numeric fields,
not argument/event terms. Descriptor and list visits share a 1..4096 event budget.
Native tuple recursion is limited by validated depth, and call parsing uses a
fixed 255-term stack array. CAS retry contention and VM overhead are not a hard
wall-time budget.

The clause compiler bounds sixteen clauses, eight arguments and 256 annotated
metadata nodes per clause. Its generated VM match specification and Bylaw's
loaded metadata are outside the native payload figures. RSS measurements include
those structures, but do not isolate their compiled VM storage. Larger scope
must not be described as having a proven total memory bound from the native
payload alone.

[OTP's trace-session documentation](https://www.erlang.org/doc/apps/kernel/trace.html#session_destroy/1)
describes removal of trace settings on session destruction; previously sent trace
messages are excluded from that cleanup. Native callbacks avoid that mailbox.
The tests provide additional shutdown evidence, not a universal scheduler timing
proof. The code-change guard invalidates on any load/delete attempt, including
unrelated or unsuccessful attempts. It deliberately does not silently resume
coverage across a changed module.

Approved revisions are Ecto 11784f821a1bb0eedeee59583e311d836cb39ee1 and Livebook
f18f2035bac89d6c08497f5f2d7e7c4f56e80716. In three combined Livebook cycles,
from_compressed/1 retained all 18 counters across 65536 calls/returns per cycle,
unchanged results and module MD5. Ecto.UUID.cast/1 raw-mode cycles were exact,
but its generated combined plan rejects unsupported loader metadata. Its clause
patterns also exceed this translator's vocabulary. These are focused function
exercises, not full application suites. The external JSON artifacts retain
successful, rejected and historical stages separately.

The actionable alternative to default adoption is a separately scoped general
bounded type/pattern interpreter and integration adapter: reject unsupported
modules before starting, map every declared target to a stable counter, retain
explicit work-exhaustion/reload states, and compare full supported-module reports
with existing checks. Container/binary patterns and unsupported alias metadata
must have reproducible acceptance coverage before claiming Ecto support. A
subsequent adoption decision also needs full-application QA, platform validation
beyond the tested ARM64 environment, compiled match-spec memory accounting and
caller-cost limits appropriate to real workloads. Keeping the default bounded
observer while retaining this experiment is the current supported decision.
