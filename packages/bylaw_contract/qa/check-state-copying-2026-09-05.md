# Check-state copying — 2026-09-05

Beads: `bylaw-contract-reduce-check-state-copying`.
Baseline Bylaw: `8431d36ed2d8ba0a1d53d2e9b09ffd8672cf577e`.
QA repository: the approved Livebook checkout at
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`, located at
`/tmp/bylaw-reasons.oRUJf0/livebook`. Runtime: Elixir 1.20.2 / OTP 29.
No other external repository was accessed for this task.

## Problem and implementation

Check initialization previously ran in the tracer before copying the complete
runtime into a worker. Inter-process copies expanded shared terms. Typespec
state duplicated targets in lists and lookup indexes, structural state retained
compile-only classifier AST, and stop duplicated standard fields under `checks`
before sending the result to the caller.

Checks now initialize sequentially in their owning workers. Only claims cross
back to the tracer during initialization. Trace sessions activate after all
checks initialize successfully. Typespec indexes hold IDs into one target map;
structural workers discard classifier AST after compiling the shadow module.
The caller assembles standard fields and per-check coverage after receiving
individual check results, preserving the public result shape and term sharing.

The lifecycle change requires trapping linked exits so prior workers can clean
up on failed initialization or activation. Abnormal worker exits still stop the
tracer and its siblings. This does not promise callback cleanup after an
untrappable kill of the owning process.

The full package suite also exposed self-instrumentation: the compiler check
selected the tracer's new exit handler, then hot-reload restoration killed the
active tracer. Compiler instrumentation now rejects Tracer, TraceWorker,
CompilerObserver, and Check.ElixirCompiler with an explicit warning. Affected
alternatives remain unknown and are excluded from actionable misses.

## Regression evidence

The six initial acceptance tests ran empty, then their bodies reproduced four
failures before implementation. A shared fixture occupied 2,060 words at check
initialization but 42,060 words after worker startup. The owner PID differed
between initialization and termination, final standard/per-check fields lost
sharing, and structural workers retained classifier AST.

Further tests cover ordered claims, initialization failure cleanup, activation
failure cleanup, abnormal sibling exit, concurrent observers, compact typespec
indexes, and compiler runtime exclusion. The index regression measured 1,348
flat state words against a threshold of 1,023 before the index change. The
compiler exclusion regression confirmed that Tracer was actually instrumented.
All 109 package tests pass after implementation, including the existing nested
ExUnit compiler-observation subprocess test. Strict Credo and repository-wide
`scripts/qa.sh` pass, including 974 UI tests.

## Approved repository measurements

`qa/check-state-memory.exs` compiles the selected Bylaw source into a fresh VM,
loads existing Livebook test BEAMs, and measures initialization and actual worker
state. It then executes a controlled application call, stops the observer, and
records the returned coverage. The comparison artifact contains the full
coverage map, summary, and human-readable report, serialized deterministically.
The application is not started, rebuilt, or edited.

| Probe and location | Baseline shared bytes | New shared bytes |
| --- | ---: | ---: |
| Notebook typespec state after direct init | 145,488 | 150,392 |
| Notebook typespec state inside worker | 334,800 | 150,392 |
| Notebook returned coverage | 332,680 | 167,016 |
| Delta.Operation structural state after direct init | 22,624 | 7,408 |
| Delta.Operation structural state inside worker | 31,040 | 7,408 |
| Delta.Operation returned coverage | 14,144 | 7,560 |

The new target map/ID indexes slightly increase directly initialized shared
state, but eliminate repeated target payloads: Notebook flat state decreases
from 348,928 to 215,000 bytes. The structural worker drops 18,944 flat bytes of
classifier AST. Returned coverage flat sizes remain identical at 346,784 and
18,376 bytes respectively; its actual sharing improves in the caller.

Both before/after result artifacts compare byte-identically, including full
coverage, summaries, and printed reports. Calls used:

- Typespec: `Livebook.Notebook.valid_file_entry_name?("notes.txt") == true`.
- Structural: `Livebook.Text.Delta.Operation.split_at({:retain, 4}, 2)` returns
  `{{:retain, 2}, {:retain, 2}}`.

Run from `packages/bylaw_contract` with the baseline extracted using
`git archive` and the pinned Livebook checkout supplied explicitly:

```sh
mise exec -- elixir qa/check-state-memory.exs "$BASELINE_PACKAGE" "$LIVEBOOK" typespec Livebook.Notebook /tmp/notebook-before.term
mise exec -- elixir qa/check-state-memory.exs . "$LIVEBOOK" typespec Livebook.Notebook /tmp/notebook-after.term
cmp /tmp/notebook-before.term /tmp/notebook-after.term
mise exec -- elixir qa/check-state-memory.exs "$BASELINE_PACKAGE" "$LIVEBOOK" structural Livebook.Text.Delta.Operation /tmp/operation-before.term
mise exec -- elixir qa/check-state-memory.exs . "$LIVEBOOK" structural Livebook.Text.Delta.Operation /tmp/operation-after.term
cmp /tmp/operation-before.term /tmp/operation-after.term
```

Sizes use `:erts_debug.size/1` and `flat_size/1` multiplied by word size. They
measure reachable terms, not RSS, peak allocation, or off-heap binary storage.
Worker sizing executes inside `:sys.replace_state/2`; that diagnostic also
returns a copied state to the caller, so it is unsuitable for measuring peak
memory. No whole-Livebook test-suite or whole-project RSS result is claimed.
Event queues and the unavoidable coverage payload still consume memory; this
change does not impose a global memory budget or introduce ETS/persistent_term.
