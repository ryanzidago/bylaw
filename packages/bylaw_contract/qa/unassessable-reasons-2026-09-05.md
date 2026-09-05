# Compiler coverage reason investigation — 2026-09-05

Issue: `bylaw-contract-investigate-unassessable-reasons`.
Library baseline: `fe146d56` (runtime code unchanged from
`1e42a14ca3eadec14fa0442f04b1f9101c83763d`).

## What the counters mean

`Report.summary/1` first filters compiler alternatives by `supported?`, then
removes IDs in `coverage.unknown`. Only the remaining alternatives contribute
to `supported_compiler_return_alternatives`. Thus “supported” in the summary
means assessable **in this observation**, not merely a supported type shape.
An instrumented, inferable function with no calls produces two unsupported
alternatives and zero warnings in the new deterministic regression fixture.

The exact denominator identities are:

- total compiler alternatives = assessable + unassessable;
- assessable = observed + missed;
- compiler unsupported modules count failed module inspections, not alternatives;
- compiler warnings count messages, not distinct modules or alternatives.

A failed module has no decoded alternatives. Its missing alternatives are not
included in the alternative denominator. It is incorrect to add unsupported
modules to unsupported alternatives, or interpret 0/0 alternatives as complete
coverage. The default report correctly excludes unassessable targets from misses.
Compiler hit values are presence markers, not counts of returned values;
`compiler_call_events` sums injected clause counters.

## Pipeline and evidence

All paths refer to `lib/bylaw/contract/` in this package.

| Cause or exclusion | Code and existing evidence | Counting effect |
| --- | --- | --- |
| Object code unavailable | `compiler_inference.ex`, `read_module/1`; new in-memory-module test | Unsupported module, no alternatives; module reason and warning retained |
| Missing ExCk chunk | `read_module/1`; new stripped-chunk test | Unsupported module; raw BEAM reader reason retained |
| Unsupported checker version | `decode_chunk/1`; existing future-version fixture | Unsupported module with explicit version |
| Inferred signatures absent | `inferred_signatures_present/1`; existing `infer_signatures: false` fixture | Unsupported module, even with a recognized checker format |
| Unsafe/corrupt encoded term | `decode_chunk/1`; new corrupt-chunk test | Unsupported module with safe-decoding reason |
| Descriptor decoding failure | `compiler_inference/elixir_1_20.ex`, `return_alternatives/2`; new malformed-descriptor fixture | Whole module unsupported, not a partial alternative inventory |
| Inspection timeout/crash | `compiler_inference.ex`, `isolated/1` and `load_module_isolated/2` | Whole module unsupported; 100 ms timeout or process-exit text retained. 17 cold Changelog timeouts measured below; not forced by a timing-sensitive test |
| Unknown authorship | `authored_mfas/2`, `merge_authorship/3`; existing no-debug-info fixture | Module may stay supported; retained alternatives become unknown, with a module warning |
| Generated definitions / protocol implementations | `authored_definition?/1`, `protocol_implementation?/1`; existing generated/protocol fixtures | Intentionally excluded, not unassessable obligations |
| Earlier check owns the return contract | `check/elixir_compiler.ex`, `init_with_limit/3`; existing Registration fixture | Removed before compiler obligation counting |
| Unsupported return shape | `CompilerTypeMatcher.supported?/1`; matcher unknown-shape fixtures | Excluded by the report regardless of unknown membership |
| Non-finite return group | `finite_discriminant?/1`, `inferable_ids/2`; existing open-ended-list fixture | All alternatives in the group non-inferable, including individually finite members |
| Unsupported input shape | `arguments_supported?/2`, `inferable_ids/2`; new open-tuple input fixture | One unsupported rule disables inference for the entire function |
| Ambiguous input-to-output rules | `inferable_ids/2`; existing single-clause `if` fixture | An alternative needs at least one singleton output rule; otherwise unknown |
| Function cap | `limit_functions/2`; existing alpha/omega fixture | Inferable MFAs sorted by Erlang term order; first 10 selected by default; omitted alternatives unknown, one aggregate warning |
| Instrumentation failure | `instrument_module/3`; new sticky-module fixture | Compiler module still supported; selected alternatives unknown and module warning retained |
| No observed call | `coverage/1`, `unobserved_function_alternatives/2`; new no-call fixture | All selected alternatives of the uncalled function unknown, without a warning |

`initial_unknown` unions non-inferable authored alternatives, unknown-authorship
alternatives, cap omissions and failed instrumentation. `coverage/1` adds
uncalled selected functions. These lifecycle stages can provide a disjoint
partition if applied in that order, but diagnostic shape flags overlap:
non-finite output, unsupported input, unsupported return and lack of a singleton
rule must not be summed. Absence of a call is only knowable for successfully
instrumented functions; a cap omission is not evidence of no execution.

## Reproduction

The new `test/compiler_unassessable_reasons_test.exs` contains seven runnable
characterization tests. Their empty inventory ran successfully before bodies
were filled. All seven pass against unchanged runtime code; no failing behavior
regression or runtime fix is claimed. Existing acceptance tests cover the
complementary paths listed above.

```sh
mise exec -- mix test test/compiler_inference_acceptance_test.exs \
  test/compiler_type_matcher_test.exs test/compiler_unassessable_reasons_test.exs
```

`qa/compiler-reasons.exs` inspects compiled application modules in a fresh VM,
using the selected runtime's compiler descriptor implementation. It compiles
Bylaw source in memory, loads the target application's BEAM paths, and reports
module reasons, earlier Typespec claims, authored alternatives, cap selection,
and overlapping inference flags. It neither starts the target application nor
runs tests or instruments target modules. Use the same runtime that compiled
the target to avoid descriptor/toolchain mismatch. The script deliberately
keeps this investigation out of the public API.

## External evidence

The original QA clones were moved to Trash. On this machine,
`ls /Users/ryanzidago/.Trash` fails with `Operation not permitted`; the original
`/tmp/bylaw-contract-qa.Ef0vbA` is absent. Therefore old runtime unknown sets and
module reasons cannot be reconstructed from the aggregate report. Fresh pinned
checkouts below are independent static measurements, not a replay of the old
runtime observations. In particular, they cannot attribute the old Livebook
304 unassessable alternatives to cap omissions versus unobserved functions.

Fresh checkout root: `/tmp/bylaw-reasons.oRUJf0`. Both tracked checkouts remained
clean, including their lockfiles, after dependency fetch and compilation.

| Project | Pinned revision | Compilation runtime |
| --- | --- | --- |
| Changelog | `3e46efd3773e9c375633d49d9353608f294da15d` | Elixir 1.18.3 / OTP 27.3.3 |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | Elixir 1.20.2 / OTP 29.0.3 |

In each checkout, run `MIX_ENV=test mise exec elixir@VERSION erlang@VERSION --
mix deps.get`, followed by the same prefix with `mix compile`. Both builds
succeeded. Livebook emitted an optional `:aws_credentials` unavailable warning;
Changelog emitted upstream dependency warnings. Neither command runs services
or tests. Then, from this package directory:

```sh
mise exec elixir@1.18.3-otp-27 erlang@27.3.3 -- \
  elixir qa/compiler-reasons.exs /tmp/bylaw-reasons.oRUJf0/changelog changelog
mise exec elixir@1.20.2-otp-29 erlang@29.0.3 -- \
  elixir qa/compiler-reasons.exs /tmp/bylaw-reasons.oRUJf0/livebook livebook
PRELOAD_MODULES=1 mise exec elixir@1.20.2-otp-29 erlang@29.0.3 -- \
  elixir qa/compiler-reasons.exs /tmp/bylaw-reasons.oRUJf0/livebook livebook
```

`PRELOAD_MODULES=1` loads all modules listed by the target application before
inspection; it does not start that application or preload every dependency.

| Measurement | Changelog cold | Livebook cold | Livebook preloaded |
| --- | ---: | ---: | ---: |
| Modules | 350 | 355 | 355 |
| Supported modules | 0 | 243 | 246 |
| Unsupported checker version | 333 | 0 | 0 |
| Inspection timeout | 17 | 0 | 0 |
| Safe-term decoding rejection | 0 | 79 | 75 |
| Descriptor decoding failure | 0 | 29 | 30 |
| Inferred signatures absent | 0 | 4 | 4 |
| Raw decoded alternatives | 0 | 351 | 377 |
| Claimed by Typespec | 0 | 116 | 140 |
| Generated exclusions after decoding | 0 | 7 | 7 |
| Retained authored alternatives | 0 | 228 | 230 |
| Unknown authorship | 0 | 0 | 0 |
| Non-inferable authored alternatives | 0 | 218 | 220 |
| Inferable alternatives | 0 | 10 | 10 |
| Selected functions / alternatives | 0 / 0 | 5 / 10 | 5 / 10 |
| Cap omissions | 0 | 0 | 0 |

A further Changelog run with `PRELOAD_MODULES=1` measured 339 version failures
(`:elixir_checker_v1`) and 11 timeouts, again 350 unsupported modules and zero
alternatives. Example timeout: `Changelog`; example version rejection:
`Changelog.AgentKit`. The 100 ms budget includes module reading and decoding;
preloading did not remove every timeout. The cold timeout count is an observed
run result, not an invariant or evidence of a corrupt descriptor.

The overlapping flags on Livebook authored alternatives are: unsupported return
shape 2 cold / 3 preloaded; non-finite return group 190 / 192; unsupported input
group 0 / 2; no singleton output rule 214 / 214. These are overlapping counts
out of 228 / 230, not a partition. Cap exclusions are zero for these fresh
static inventories, but that does not establish the cap's effect in the old
309-alternative runtime inventory. No-call and instrumentation-failure counts
are **unmeasured** here, not zero.

The change from 79 to 75 safe-decoding failures demonstrates a load-state effect;
it does not prove that all such failures have the same cause. Investigation
`bylaw-contract-investigate-safe-checker-decoding` records the next steps without
proposing removal of safe decoding.

### Confirmed decoder defect

The preloaded Livebook scan contains 30 descriptor decoding failures. A common
message is a clause label missing from the normalized union's label map, for
example `Livebook.Session.Data.apply_operation/2` looking up `:error` when only
`atom()` remains. The following independent valid descriptors reproduce this
failure without Livebook:

```elixir
alias Module.Types.Descr
exports = [
  {{:choose, 1},
   %{sig: {:infer, nil, [
     {[Descr.atom([:one])], Descr.atom([:ok])},
     {[Descr.atom([:two])], Descr.atom()},
     {[Descr.atom([:three])], Descr.integer()}
   ]}}}
]
Bylaw.Contract.CompilerInference.Elixir120.return_alternatives(Example, exports)
# {:error, "could not decode ... key \":ok\" not found in ..."}
```

The union correctly absorbs `:ok` into `atom()`, but the clause mapping still
uses `Map.fetch!` on the original rendered label. This discards the entire
module. `bylaw-contract-handle-normalized-return-unions` tracks a conservative
fix and failing acceptance tests separately; this investigation does not
change runtime behavior or assert that every decoder failure shares that cause.

## Validation

The existing compiler acceptance and matcher suites passed (26 tests). The
seven-test empty inventory passed, followed by all seven implemented
characterization tests. The complete package suite passed **84 tests** and
strict Credo found no issues. Repository-wide `mise exec -- scripts/qa.sh`
passed all package gates and **974 UI tests**. The diagnostic script was also
formatted explicitly because `qa/` is outside the default formatter inputs.

## Recommendation

Preserve conservative assessment and current default output. The smallest
useful future change is a programmatic map from compiler alternative ID to a
set of reason atoms, populated where each exclusion occurs, alongside existing
module status/reason records. Suggested lifecycle reasons: `unknown_authorship`,
`non_inferable`, `function_limit`, `instrumentation_failed`, `unobserved_function`.
Keep shape/ambiguity detail as potentially overlapping subreasons of
`non_inferable`; do not invent a single exclusive root cause.

Regression criteria for that separate change: reason keys refer only to retained
compiler alternatives; the reason-map keys equal the compiler unknown set;
no-call reasons disappear after an observed call; cap/instrumentation reasons
remain distinct from no-call; earlier claimed/generated contracts do not gain
reasons; unknown alternatives never print as misses. Preserve independent
unsupported-return shape information because `supported? == false` is a separate
report filter. Do not rename existing counters or broaden inference as part of
adding diagnostics. Cap selection/coverage tradeoffs belong to
`bylaw-contract-investigate-instrumentation-cap`.
