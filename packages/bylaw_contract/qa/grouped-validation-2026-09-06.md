# ExUnit grouping and resource isolation

Beads: `bylaw-contract-investigate-exunit-grouped-validation`, under
`bylaw-performance`. This study asks whether Bylaw.Contract's own validation suite
can overlap independent work while preserving its existing cases, assertions and
isolation. The adopted two-group layout lowers median validation wall time from
42.52 to 29.87 seconds, with sampled peak memory rising from 331.1 to 438.0 MiB.
All paired runs pass the same 264 tests. It does not change contract observation
scope or production defaults.

## Resource inventory and candidate

The baseline is main revision `21d87ee04b52140cb7fda4e86e12c8614cf44253`, following
the concurrency study in PR297. The installed runtime is Elixir 1.20.2 / OTP29.0.3.
Both the installed source and `mix usage_rules.docs ExUnit.Case` confirm the
[documented group semantics](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/ex_unit/lib/ex_unit/case.ex):
async cases in one group run serially, while different groups may overlap.
Synchronous cases run after the async phase. A group does not protect arbitrary
VM-wide state, nor does it serialize native test-file loading.

The candidate changes only seven outer `use ExUnit.Case` declarations. It creates
two groups of subprocess-based cases; all in-VM observation and global-mutation
cases retain their baseline scheduling. Existing assertions, test bodies, timeouts,
fixtures, source locations, helper behavior and compiler settings are unchanged.
There is no parameterization candidate: these cases exercise different scenarios
and state transitions, and no equivalent duplicated setup was identified that
would justify changing their test inventory.

| Test file | Candidate scheduling | Resource ownership / reason |
| --- | --- | --- |
| `formatter_colors_test.exs` | `:contract_formatter` | Color state, fixture compilation and observers live in a child VM; parent owns a unique temporary directory. |
| `formatter_diff_git_acceptance_test.exs` | `:contract_formatter` | Each case owns synthetic Git repositories and child Mix runs; `FormatterDiff` passes a scrubbed Git environment. |
| `formatter_diff_scope_acceptance_test.exs` | `:contract_formatter` | Same helper and child-VM boundary; grouping bounds concurrent formatter commands. |
| `compiler_safe_decoding_test.exs` | `:contract_qa_fixture` | Cold atom/checker state is tested in fresh compiler/Elixir children; parent-owned unique temporary files are removed on exit. |
| `concurrency_acceptance_test.exs` | `:contract_qa_fixture` | Builds/runs the shared performance fixture; must serialize with warm-session tests. |
| `warm_session_acceptance_test.exs` | `:contract_qa_fixture` | Uses the same fixture build directory and bounded child runner. |
| `overhead_capture_acceptance_test.exs` | `:contract_qa_fixture` | Previously async without a group; child ETF decoding and unique temporary paths join the same bounded subprocess group. |
| `compiler_clause_mapper_test.exs` | Existing ungrouped async | Pure mapping examples; unchanged. |
| `diff_scope_exploration_test.exs` | Existing synchronous | Mutates the parent VM's `GIT_DIR`, `GIT_WORK_TREE` and `GIT_INDEX_FILE`; subprocess use elsewhere in the file does not make the whole case independent. |
| `report_colors_acceptance_test.exs` | Existing synchronous | Mutates ANSI application state and Bylaw environment variables. |
| `compiler_cap_acceptance_test.exs` | Existing synchronous | Changes compiler options and loads/purges generated modules. |
| `compiler_inference_acceptance_test.exs` | Existing synchronous | Compiler-option changes, generated modules and instrumented target code. |
| `compiler_unassessable_reasons_test.exs` | Existing synchronous | Compiler-option changes, disk BEAMs, sticky code-path behavior and module purge/load. |
| `function_selection_acceptance_test.exs` | Existing synchronous | Compiler options and deliberate load/purge of shared support modules. |
| `source_selection_acceptance_test.exs` | Existing synchronous | Dynamically compiled source fixture modules. |
| `structural_coverage_test.exs` | Existing synchronous | Compiler-option changes and generated module replacement. |
| `structural_eliminated_private_test.exs` | Existing synchronous | Generated/rewritten BEAMs and compiler-option changes. |
| `trace_backlog_acceptance_test.exs` | Existing synchronous | Compiler options, tracing, suspended/killed workers and bounded queue fixtures. |
| `typespec_expansion_test.exs` | Existing synchronous | Compiler-option changes, temporary source/BEAM files and generated module cleanup. |
| `check_selection_acceptance_test.exs` | Existing synchronous | Includes formatter initialization against the whole current application. |
| `check_state_ownership_test.exs` | Existing synchronous | Worker failure/termination, shared structural shadow pool and fixture calls. |
| `check_caller_context_test.exs` | Existing synchronous | Shared caller fixture and exact observed events. |
| `compiler_normalized_union_test.exs` | Existing synchronous | Compiler observation rewrites/restores shared target modules. |
| `compiler_source_clause_mapping_test.exs` | Existing synchronous | Original-code replacement/restoration and exact compiler counters. |
| `generic_behavior_acceptance_test.exs` | Existing synchronous | Observers, shared protocol fixtures, spawned callers and exact counters. |
| `improper_list_acceptance_test.exs` | Existing synchronous | Includes real observation of the shared improper-list fixture. |
| `migration_acceptance_test.exs` | Existing synchronous | Multiple shared fixtures, observers and exact reports/counters. |
| `report_test.exs` | Existing synchronous | Includes real structural observation and report assertions. |
| `return_alternative_observation_test.exs` | Existing synchronous | Shared return fixtures and overlapping observer lifetime assertions. |
| `spec_observation_test.exs` | Existing synchronous | Shared fixtures and exact call/return counts. |
| `structural_caller_guard_test.exs` | Existing synchronous | Shared caller fixture, children and generated classifiers. |
| `structural_caller_variable_test.exs` | Existing synchronous | Direct use of the shared structural shadow-module pool. |
| `structural_count_accumulation_test.exs` | Existing synchronous | Exact shared-fixture structural counters. |
| `structural_joint_outcomes_test.exs` | Existing synchronous | Same structural fixture/counter ownership. |
| `compiler_type_matcher_test.exs` | Existing synchronous | Pure descriptor matching; unnecessary scheduling changes avoided. |
| `type_expansion_limit_test.exs` | Existing synchronous | Local counters/resolver; unchanged. |
| `type_matcher_test.exs` | Existing synchronous | Pure matching examples; unchanged. |
| `source_selection_unresolved_test.exs` | Existing synchronous | Source parsing examples; unchanged. |
| `incomplete_report_colors_test.exs` | Existing synchronous | IO capture and report rendering; unchanged. |
| `process_metrics_acceptance_test.exs` | Existing synchronous | Short Python subprocess regressions; unchanged. |
| `grouped_capture_acceptance_test.exs` | Synchronous in both controls | Three new capture/audit acceptance cases, including deliberately failed/leaking child suites. |

The two groups bound the number of simultaneous heavy test-command families to
two. This is a suite-specific resource decision, not a claim that the host has a
hard CPU or memory bound. The 32 structural shadow modules form a shared pool;
grouping each apparent fixture separately would not isolate that pool or prevent
extra calls from reaching other observers' counters.

## Capture validation and controls

Three named acceptance cases ran empty, then their bodies exposed the missing
capture before implementation. The native ExUnit recorder retains every finished
test's identity, source location, outcome, failure and duration, plus module/group
intervals and native suite timings. Interval endpoints are formatter receipt
timestamps, not precise process execution boundaries. A synchronized two-group
fixture proves real overlap independently of those timestamps, while two members
of one group remain serial.

The audit runs after Mix's ordinary cleanup and compares working directory,
compiler options, ANSI configuration and the Bylaw/Git environment keys actually
mutated by the suite. It checks live contract workers, generated shadow modules,
trace sessions and restoration of original compiled module MD5s. It preserves
failed tests and reports resource leaks separately; a leak changes an otherwise
successful process to exit 2. Independent review exposed an omitted Git-environment
check; a regression ran red before those keys were added.

Baseline and candidate use separate session-owned linked worktrees, both at the
same library revision. Both include the identical recorder and its three tests.
`run-grouped-validation.py` rejects differences in library source, capture source
or test bodies after normalizing only the outer case declaration. Every command
uses ordinary native `mix test`, a fresh VM, warmed application builds and the
same seed within its pair. Normal compilation/case defaults remain in effect.
No cases are excluded, no timeout is raised, and no trace/slowest option is used.

The runner alternates baseline/candidate order, uses three fixed-seed pairs and
three varied seeds, and retains all outcomes. Each child has a 180-second external
deadline and 1536 MiB sampled process-tree cutoff. Sampling about every 100 ms can
miss short peaks and can double-count shared pages. It records native wall/CPU
counters, simultaneous process-tree RSS, exact test inventory, source stability
and remaining paths in each command's dedicated temporary directory.

## Baseline resource finding

Before any scheduling change, the first baseline passed 264 tests across 41 cases
but left `StructuralCoverage.Shadow1` loaded. The audit correctly returned exit 2;
workers, trace sessions, original module MD5s and global settings were restored.
The independent reviewer reproduced the cause with one structural observer:
killing its worker leaves the generated shadow loaded after the tracer exits.
The existing abnormal-worker-exit test checks sibling termination but not that
shadow. This is tracked as deferred
`bylaw-contract-release-shadow-after-worker-kill`; the grouping task does not
change abrupt-death resource ownership. Measurements must retain this finding and
cannot claim a fully clean suite merely because all assertions pass.

## Repeated results and adoption

All six pairs execute the same 264 declarations across 41 cases, as independently
parsed by `grouped-validation-inventory.exs`. Every case passes in every run; the
three new recorder acceptance cases are present in both layouts. All seven grouped
modules have the expected effective group; each group is serial and the two groups
overlap. Both layouts retain exactly the same known Shadow1 leak, with no remaining
workers/sessions, changed original modules or global-setting differences. Thus all
twelve audit commands correctly exit 2, and the aggregate runner exits nonzero.
These exit codes are retained rather than converted to success.

| Pair | Seed | Baseline wall, s | Grouped wall, s |
| --- | ---: | ---: | ---: |
| 1 | 922331 | 41.73 | 28.90 |
| 2 | 922331 | 42.32 | 28.99 |
| 3 | 922331 | 42.94 | 29.96 |
| 4 | 31 | 43.19 | 30.29 |
| 5 | 173 | 42.71 | 29.77 |
| 6 | 9001 | 42.05 | 29.97 |

| Metric | Baseline median [range] | Grouped median [range] |
| --- | ---: | ---: |
| Native wall, s | 42.52 [41.73, 43.19] | 29.87 [28.90, 30.29] |
| Native CPU, s | 10.62 [9.99, 11.50] | 10.07 [9.83, 10.97] |
| Sampled simultaneous tree RSS, MiB | 331.1 [294.8, 390.4] | 438.0 [400.4, 465.7] |
| Native ExUnit suite, s | 41.97 [41.12, 42.64] | 29.29 [28.39, 29.72] |

Wall time falls 28.7–31.5% within the six pairs. The groups' observed intervals
overlap for a median 14.68 seconds. Native async-phase time grows from a median
1.29 to 21.31 seconds as previously synchronous subprocess work moves there;
total suite time falls. These intervals overlap and must not be added as exclusive
phases. CPU ranges overlap, while median sampled peak RSS rises about 32%.
The benefit comes from overlapping existing work, with no intrinsic contract
classification-cost reduction established. These are small repeated samples on
one shared machine, not confidence intervals or a hard memory guarantee.

Adopt the seven declaration changes: the roughly 12.65-second median reduction is
consistent across fixed and varied seeds, and explicit child-VM boundaries preserve
the audited isolation while shared fixture builds remain serial. The higher memory
peak is the measured cost of this repository-specific choice. Existing parent-global
cases stay synchronous. The pre-existing abrupt-worker shadow leak remains deferred
and prevents a claim that the entire suite leaves no resources behind; it does not
appear or increase when the two subprocess groups overlap.

The initial baseline and pilot are also retained. The pilot passes 264 tests in
each layout (40.63 versus 29.17 seconds) with the same cleanup finding. No command
hits its deadline or memory cutoff. Under each command's unique temporary root,
only native Mix lock/pubsub paths remain; no fixture source, BEAM or repository
directories remain there. The pinned native
[lock implementation](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/mix/lib/mix/sync/lock.ex)
intentionally retains stale lock files, and
[pubsub cleanup](https://github.com/elixir-lang/elixir/blob/v1.20.2/lib/mix/lib/mix/sync/pubsub.ex)
also handles stale subscription paths lazily. These paths are recorded rather
than treated as proof of live processes or deleted to manufacture a clean audit.

## Reproduction and external QA

Use two dedicated linked worktrees, with the baseline at the recorded parent
revision and the candidate containing this change. Copy only the new recorder and
its acceptance test into the baseline so both layouts execute the same inventory;
retain the baseline's original case declarations. From the candidate package:

```sh
cp qa/grouped-suite-capture.exs "$BASELINE/qa/grouped-suite-capture.exs"
cp test/grouped_capture_acceptance_test.exs "$BASELINE/test/grouped_capture_acceptance_test.exs"
(cd "$BASELINE" && MIX_ENV=test mise exec -- mix compile)
MIX_ENV=test mise exec -- mix compile
mise exec -- python3 qa/run-grouped-validation.py "$BASELINE" "$PWD" /tmp/grouped-comparison
mise exec -- elixir qa/grouped-validation-inventory.exs
```

`BASELINE` names its `packages/bylaw_contract` directory, not the repository root.
The runner accepts different Git HEADs but requires identical library source,
capture source and normalized test bodies, then checks source stability after
each command. The overly strict initial HEAD-equality gate was removed after the
completed measurements so a committed candidate can be compared with its parent;
this did not change measured workloads. Original measured runner hashes and pins
remain in the artifact.

Preferred compatible external QA also passes with unchanged checkouts. Both the
disabled and default-check Ecto commands pass 1,591 tests at revision
`11784f821a1bb0eedeee59583e311d836cb39ee1`; both Livebook commands pass 1,511 with
185 existing exclusions at `f18f2035bac89d6c08497f5f2d7e7c4f56e80716`. Default-check
observation remains incomplete at the unchanged queue budget in both applications.
No external case, timeout, fixture or configuration is changed. Historical
Realtime/LiveView toolchains remain incompatible with current Bylaw's Elixir
requirement and are not upgraded for this study.

`grouped-validation-results.json` retains the initial baseline, pilot, all repeated
commands and every test identity/outcome/duration, source manifests, cleanup results
and external QA summaries. External per-test timing arrays are summarized, with raw
JSON, logs and ETFs under `/tmp/bylaw-grouped-20260906/external`; the repeated-suite
records retain full per-test values. The reader can compare the declaration oracle
with each capture without trusting a successful process exit or averaging coverage
percentages.

Repository-wide `scripts/qa.sh` passes, including all 974 UI tests. Independent
review reproduced the two audit findings, confirmed the Git-environment regression
is fixed, and verified all 12 formal records, the declaration oracle, reported
statistics, external outcomes and the corrected source gate. No reproducible
critical finding remains in this change.
