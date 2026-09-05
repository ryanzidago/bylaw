# Bounded typespec expansion — 2026-09-05

Beads: `bylaw-contract-bound-typespec-expansion`.
Baseline: Bylaw `5bbdc2ffaac2317d6f8ce9158587c1c5ad1d6eed`.
External QA uses the approved Livebook repository only, pinned at
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716` in the disposable checkout
`/tmp/bylaw-reasons.oRUJf0/livebook`. Its existing test BEAMs were inspected
without changing or starting the application.

## Problem and change

A repeated alias definition `tN() :: {tN_minus_1(), tN_minus_1()}` previously
materialised exponentially growing match trees. Explicit graph references now
preserve sharing even when state crosses process boundaries. Alias resolution
includes parameter bindings and recursion context. Unsupported containers stop
expanding and retain a compact reason; unsupported lists keep length partitions.
Function signatures are not expanded because matching only checks arity.

Each match graph permits 4,096 uncached alias resolutions. Top-level union
flattening permits 4,096 AST visits per root before constructing targets. Either
limit produces an explicitly unsupported target rather than an incomplete set
of assessable alternatives. These are expansion bounds, not a whole-application
memory limit; the original AST, target count, and runtime values remain inputs
to memory usage.

## Reproduction

Run from `packages/bylaw_contract`, using the pinned baseline source extracted
with `git archive` and the approved Livebook checkout as explicit paths:

```sh
mise exec -- elixir qa/typespec-memory.exs "$BASELINE_PACKAGE" synthetic
mise exec -- elixir qa/typespec-memory.exs . synthetic
mise exec -- elixir qa/typespec-memory.exs "$BASELINE_PACKAGE" real "$LIVEBOOK" Livebook.Notebook
mise exec -- elixir qa/typespec-memory.exs . real "$LIVEBOOK" Livebook.Notebook
mise exec -- elixir qa/typespec-metadata.exs "$BASELINE_PACKAGE" "$LIVEBOOK" livebook /tmp/typespec-before.term
mise exec -- elixir qa/typespec-metadata.exs . "$LIVEBOOK" livebook /tmp/typespec-after.term
cmp /tmp/typespec-before.term /tmp/typespec-after.term
```

The synthetic script writes and loads its own persisted fixture BEAMs, then
removes them. The metadata script inspects one module per bounded worker
(20 million heap words, 30-second timeout), excludes only `match_type`, and
sorts target maps and uses deterministic term serialization before writing the
comparison artifact. It includes IDs,
labels, supported flags, boundaries, and source locations. It does not compare
runtime hit counts or warning lists.

## Measurements

Shared and flat sizes are Erlang term words multiplied by machine word size.
They are not VM RSS and exclude off-heap binary storage. Diagnostic sizing
time is not a library latency benchmark.

| Synthetic depth | Baseline shared bytes | New shared bytes | Baseline flat bytes | New flat bytes |
| --- | ---: | ---: | ---: | ---: |
| 4 | 3,048 | 1,656 | 5,832 | 3,304 |
| 8 | 35,688 | 2,232 | 71,112 | 4,712 |
| 12 | 557,928 | 2,808 | 1,115,592 | 6,120 |

Each synthetic case retains one supported input target, unchanged metadata,
and no warnings. These measurements were initially obtained on Elixir 1.19.5 /
OTP 28 and reproduced on Elixir 1.20.2 / OTP 29, also used for Livebook.

`Livebook.Notebook` retains 149 input targets, including 94 supported targets,
with no warnings in either revision. Shared state falls from 17,259,688 to
145,488 bytes; flat state falls from 35,235,136 to 348,928 bytes. The metadata
SHA-256 is identical:
`273A4BEEF7D8B8A1A83D483E6BB89872F2B3FD0788CA26356107D84F27AD6F71`.

Across the entire compiled Livebook application, the sorted metadata artifacts
are byte-identical: 2,265 input classes (2,113 supported), 683 return alternatives
(651 supported), and no boundaries. An earlier all-module baseline worker was
killed by the diagnostic heap limit; inspecting modules separately succeeded.
That failed diagnostic is not a completed whole-application memory measurement.

## Regression coverage

The persisted-BEAM tests independently match valid and invalid values, copy
graphs through Tasks and the real tracer, distinguish parameter bindings, and
preserve recursive/opaque behavior, map keys, list partitions, and source
locations. The original representation failed the growth regression at depth 8
(4,343 flat words versus a threshold of 789). A bounded worker killed the
original repeated-union expansion; the fix returns the explicit limit marker.
A separate resolver-counter regression proves the 4,096-resolution ceiling.

All 99 package tests and strict Credo passed. Repository-wide `scripts/qa.sh`
passed, including 974 UI tests.
These static Livebook comparisons establish target preservation, not a claim
that its full runtime test suite passed with this change.

A fresh VM also exercised the current compiled package through the real tracer:

```elixir
Code.prepend_paths(Path.wildcard(Path.join(livebook, "_build/test/lib/*/ebin")))
module = Livebook.Text.Delta.Operation
{:ok, tracer} = Bylaw.Contract.start([module], checks: [Bylaw.Contract.Check.Typespec])
{{:retain, 2}, {:retain, 2}} = module.split_at({:retain, 4}, 2)
coverage = Bylaw.Contract.stop(tracer)
```

With Bylaw's test `ebin` added using `elixir -pa`, coverage recorded one
`split_at/2` call, two nested `retain/1` calls and returns, and four hit targets.
This is a controlled runtime smoke check; it does not replace the independent
valid/invalid matching and tracer assertions in the regression suite.
