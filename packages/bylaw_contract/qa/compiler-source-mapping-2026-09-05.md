# Compiler source-clause mapping regression QA

Beads: `bylaw-contract-map-normalized-rules-to-source-clauses`.
Base: Bylaw `00d03f12541f71a80333fe6585f2d667d9e42d49`.
The earlier [candidate audit](candidate-audit-2026-09-05.md) confirmed that
normalized inference rule indexes were incorrectly used as source-clause
indexes. This change maps input domains to actual source clauses before
injecting counters. It does not trace arguments or inspect returned values.

## Regression evidence

Three of the six persisted-BEAM acceptance tests failed before implementation:
discard credited keep, exercised keep remained missed, and reordered/repeated
clauses produced incorrect counts. With the fix, all six pass. Five additional
mapper tests cover rule ordering, broad forwarding clauses, guarded fallbacks,
integer-literal approximation, and inferred alternatives without source clauses.
The complete package suite passes 120 tests; strict Credo is clean.

Mapping uses conservative source-head domains. Only exact, unguarded earlier
heads are subtracted from later clauses. Each source clause must intersect
rules for one unique return alternative, and every inferred alternative must
have a mapped source clause. Ambiguous functions remain unassessable, while
independent functions in the same module remain observable. Raw input domains
are discarded after mapping; live observer state retains source-counter indexes
and output IDs. Existing function limits and code restoration remain in place.

Two older acceptance fixtures needed correction: the broad local forwarding
clause cannot identify its returned alternative from a clause counter, and the
10,000-call stress fixture now supplies explicit source branches matching its
synthetic checker rules. Local callee observation and the stress count remain
asserted. Code restoration is verified by the module MD5 and subsequent calls.

## Approved external repositories

All commands used Elixir 1.20.2/OTP 29, seed 922331, max_cases 28, with the
capture wrapper and build/run procedure from the candidate audit. Dependencies
and upstream source/test behavior were unchanged. Only the approved Phoenix
and Livebook checkouts were used.

| Repository | Pinned revision | Evidence |
| --- | --- | --- |
| Phoenix | `1e6183e9ebab9994cf6e43d3af445f32664cc10c` | Full final suite: 1,087 passed, 33 excluded. Logger-only: 11 passed. Both `compile_filter/1` alternatives have hit 1 and unknown false; the former keep miss is gone. |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | Final full rerun with no other owned heavy QA process: 1,511 passed, 185 excluded. Earlier failures are retained below. |

Phoenix's final aggregate compiler result is four assessable alternatives,
three observed, one missed. One previously counted Channel.Server alternative
is now unassessable because source clauses do not identify unique outputs.
Declared counts remain 110 missed input classes and nine missed returns.

The committed `normalized-clause-probe.exs` gives the corrected results:
keep-only records one keep hit; discard-only records one done hit and no keep
hit; done-plus-keep records two calls and both alternatives observed. All these
alternatives are assessable. This contrasts with the false-hit/false-miss table
in the earlier candidate audit.

## Livebook startup-failure comparison

Two initial candidate all-check runs passed 1,510 of 1,511 tests and excluded
185. Both failed `Livebook.Runtime.ErlDist.NodeManagerTest` at line 8 while
waiting five seconds for runtime startup. The second log includes a child-node
`Livebook.Runtime.EPMD.start_link/0` undefined-function error. An uninstrumented
full baseline and a pre-fix Bylaw all-check full run each passed all 1,511 tests.
The candidate's isolated NodeManager test also passed.

A final candidate all-check full run with no other heavy QA process owned by
this session passed all 1,511 tests, with 185 excluded, at the original seed
and max_cases 28. Concurrency within ExUnit was not reduced. This demonstrates
non-reproduction in that run, not proof that instrumentation has no effect.

Those initial candidate runs overlapped other QA processes; the comparison is
not sufficient to attribute a regression to this mapping change. Upstream
`lib/livebook/runtime/standalone.ex:221-234` deletes and recreates one shared
EPMD directory for each standalone connection. Both StandaloneTest and
NodeManagerTest are async and start standalone nodes. This is a plausible
concurrency mechanism, not a confirmed root cause. Retained logs and observations
were added to `bylaw-contract-investigate-qa-overhead`; that investigation still
requires controlled repeated pairs and individual-check isolation.

Session-local logs and trusted ETF captures are under
`/tmp/bylaw-source-mapping.7RlVWR`: `phoenix-final`, `phoenix-logger`,
`livebook-suite`, `livebook-final`, `livebook-baseline`, `livebook-old`, and
`livebook-node-manager`, and `livebook-serial-process` (the uninstrumented baseline has no ETF). These are
locators, not durable prerequisites. Recreate them from the pins and committed
capture wrapper; do not decode untrusted ETF files.

Repository validation: `scripts/qa.sh` passed, including all package checks.
