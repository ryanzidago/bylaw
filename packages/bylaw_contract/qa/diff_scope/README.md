# Formatter diff-scope exploration

Bead: `bylaw-contract-explore-pr-diff-env-var`. This is an executable design
experiment, not a released environment-variable feature. Consumers cannot use
`BYLAW_CONTRACT_DIFF_BASE` with the production formatter yet. The shipped library
and its public API are unchanged by this work.

The intended user is adopting contract observation in a codebase with existing
unobserved alternatives. Running the ordinary test suite should be able to
observe current functions changed by a chosen comparison, without imposing new
obligations on every untouched function. This selects observation targets, not
tests. It does not prove that unchanged callers or dependencies are unaffected.

## Recommendation

Keep the existing ExUnit formatter and one normal `mix test` run. Add a small
explicit function-selection option to the core, then an optional Git/environment
adapter at the formatter boundary. Do not add a Mix wrapper now: it would repeat
test argument forwarding and observer ownership without resolving the difficult
source-mapping or failure-propagation problems. The CLI exploration can evaluate
any later, concrete discovery benefit using this same selector.

Proposed core input, with names to finalize in the implementation issue:

```elixir
Bylaw.Contract.start([MyApp.Accounts], only: [{MyApp.Accounts, :register, 1}])
```

The core receives caller-owned modules and MFAs, including when the source of the
selection is not Git. It must not read environment variables, invoke Git, discover
applications, or depend on GitHub, Worktrunk, Beads, branch naming or a CI vendor.
No application configuration registry is needed. `only: []` is an intentional
empty observation, distinct from leaving the option unset. Scope must reject
unsupported custom checks explicitly rather than silently running them over the
whole application or pretending their reports are scoped.

The formatter remains the sole observer owner. It resolves selection once before
starting observation and stops once at suite completion, preserving termination
cleanup. An empty selector must start no workers or instrumentation; the test
suite still runs normally. A production implementation needs a concise explicit
empty-scope diagnostic so an empty comparison cannot be mistaken for exercised
contracts. Existing unset full-scope behavior remains unchanged.

## Proposed environment and option semantics

| Input | Result |
| --- | --- |
| `:diff_base` option omitted and environment unset | Existing full scope; do not require Git |
| Explicit `diff_base: false` | Full scope even if the environment is set |
| Explicit nonempty `diff_base: ref` | Overrides the environment |
| Environment contains a nonempty ref and no explicit option | Resolve that ref |
| Empty, whitespace-only or wrong-type value | Invalid scope diagnostic; no full-scope fallback |
| Missing Git, repository, ref, commit or common history | Invalid scope diagnostic; no empty-success fallback |
| Unresolved source mapping | Explain unsupported mapping; do not classify it as missed or complete |
| Valid comparison with no selected functions | Empty observation, ordinary tests still run |

Use explicit optional repository/source-path arguments at the integration boundary
when the working directory is not sufficient. Defaulting the prototype to `lib`
is a caller convention, not application discovery. Production must validate paths
and map selected source identities to the caller's actual loaded modules/BEAMs;
unknown modules must not disappear through an intersection with the application
module list. Explicit core-only selection needs no Git repository at all.

The prototype compares committed source only and rejects tracked modifications,
staged changes and untracked files beneath the declared source paths. It never
silently ignores dirty source. Supporting working-tree changes would require an
explicit tested-source snapshot and compiled-artifact matching policy; this
exploration does not add one. Compiled files can still be stale or compiled with
a different environment: normal Mix compilation is necessary, and proving
source-to-BEAM correspondence is an implementation requirement, not something
this parser establishes.

For an opted-in production integration, invalid or unsupported scope must produce
a nonzero outcome (recommended status 2 when no existing test failure takes
precedence). Test failures retain their normal failure status. Actionable gaps
retain the library's current observational semantics; this change should not
silently invent a coverage threshold. Incomplete scoped observation must likewise
be visibly unsuccessful, never an assessed gap report. Exact failure propagation
needs an ExUnit subprocess-tested implementation: raising in a formatter's
`init/1` alone is insufficient, as the Phoenix experiment demonstrates. The
prototype external runner therefore validates captures, completeness, stopped
state and test-failure counts independently of process exit status, returning nonzero
when any required evidence fails. It is not the final production failure mechanism.

## Comparison examples

These commands describe the proposed integration; only the QA formatter in this
directory implements the experimental environment handling today.

```sh
BYLAW_CONTRACT_DIFF_BASE=origin/main mix test
BYLAW_CONTRACT_DIFF_BASE=origin/feature-a mix test
BYLAW_CONTRACT_DIFF_BASE="$PR_BASE_SHA" mix test
```

Resolve both the explicit base ref and the checked-out `HEAD` to commit IDs, then
compare `merge-base(base, HEAD)` to that same `HEAD`. No merge is performed by
selection. Record the resolved base, common ancestor and tested head in diagnostic
evidence. Require enough fetched history to establish the actual common ancestor;
missing/shallow history is an error, not a reason to substitute `HEAD^` or an empty
tree. Rebasing or advancing the target requires recomputing the comparison.

For `main <- A <- B <- C`, A against main, B against A and C against B are per-layer
scopes. C against main is the cumulative stack scope. All runs execute the normal
tests with ancestor code present. Changes to ancestors require descendant reruns;
selection alone does not validate a stack.

In CI, supply the PR target dynamically. To observe the actual PR head, check out
that head and supply the target ref/SHA. If CI instead checks out a synthetic merge
commit, the prototype deliberately treats that merge commit as the tested head;
its comparison includes the code actually compiled/tested, including merge
resolution. Do not select against a different PR-head tree while executing a
synthetic merge tree. A future alternate head option would require equality or
explicit mapping of those source/BEAM snapshots; it is not proposed here.

## Function mapping and its limits

`source.exs` accepts maps of explicit before/after paths to source strings. It
parses source, never evaluates it, and compares authored function/spec ASTs while
retaining relevant lexical context. Repository source is trusted input, as in
ordinary compilation; parsing is not a sandbox for hostile source/atom creation.

The supported experiment selects whole current MFAs for changed bodies, heads,
guards and specs, including every current clause and callable default arity.
Deleting one clause selects the surviving function. A wholly deleted function has
no current obligation. Private definitions and multiple plain named modules are
included. Function/file renames introduce current identities; moving an otherwise
unchanged, location-independent definition does not create an obligation. Plain
formatting differences are normalized. This is source equivalence within the
supported subset, not a proof of semantic equivalence for arbitrary macros.

Critical review found and regressed several ways normalization could wrongly
return empty scope. Definition and spec fingerprints now retain the preceding
module context; default-arity specs belong to their authored definition; nested
declarations contribute their implicit aliases to following fingerprints.
Location-dependent `__DIR__`, `__ENV__` and `__CALLER__` forms are refused. Multiple
sibling nested declarations, nested modules with enclosing context and declarations
following top-level context are also refused instead of guessing lexical module
expansion.

Changed local/remote type declarations or module context produce unsupported
impact diagnostics. The prototype does not compute a transitive type/spec graph.
Changed imported macros, external types, compilation options or nondeclared source
paths cannot be treated as a complete impact analysis. Generated/conditional
function definitions are not expanded; changed generator context is unsupported.
Unchanged generated definitions do not become authored obligations. The production
mapping task must validate its supported subset against compiler-resolved identities
and either cover these cases or retain explicit unresolved results. The Phoenix
conditional-compilation change is a real example of that boundary.

## Integration points and executable experiment

The Git adapter clears repository-local Git environment variables, and fixture Git
commands also clear inherited Git variables. A regression reproduces a parent
hook context and proves selection still reads the explicitly requested repository.

The production `ExUnitFormatter.init/1` discovers the current application modules,
passes options to `Contract.start/2`, and owns its tracer lifecycle. `Tracer` starts
check workers in order; claims flow from earlier checks. Three different filtering
points are necessary:

| Check | Selection must precede |
| --- | --- |
| Typespec | Target obligations, return claims and trace interests; preferably type expansion too |
| FunctionClauses | Classifier compilation and trace interests |
| ElixirCompiler | Earlier-claim filtering, the ten-function cap and code instrumentation |

`runtime.exs` builds disposable, separately named copies of the current check
modules with selection inserted at these boundaries. It fails if an expected
source boundary no longer matches. It never rewrites the production modules or
changes budgets. Module scope narrows before each metadata loader; function
filtering currently follows metadata loading for that module. Consequently it
does not prove that function-level selection avoids all metadata expansion cost.
Generated check copies are diagnostic machinery, not a proposed shipped architecture.

`runtime_probe.exs` uses persisted generic BEAM fixtures, with a controlled checker
chunk to ensure thirteen independently known compiler-eligible functions. It
proves that the unchanged default cap omits a lexically late function and that
selection admits it before the cap, observes its counter, preserves exact typespec
and structural call counts including a child process, retains unsupported targets,
and restores the loaded module's MD5 across repeated start/stop cycles. The
compiler eligibility fixture is synthetic; real projects may have no inferable
selected function and are reported honestly.

`formatter.exs` delegates initialization and test lifecycle events to the actual
formatter. Its capture boundary stops the same tracer once and records coverage,
report cost, test counts, observation completeness and stopped state. The disabled
control starts no tracer. Copied-check compilation, Git plus source selection,
initialization, test execution, stop/reporting and memory snapshots are recorded
separately. Loading the diagnostic scripts is included only in process elapsed
time. The prototype checks that every retained target belongs to selection.

## Acceptance and implementation work

Eighteen normally runnable acceptance tests cover explicit non-Git selection,
function edits/deletions, defaults/private/multiple modules, formatting/moves,
unsupported contexts/generated/location-dependent source, option precedence,
invalid refs/dirty sources, per-layer/cumulative/synthetic-merge comparisons,
selection before cap, counters/unknowns/restoration, and the critical lexical
regressions. The initial twelve ran empty, then failed with bodies before the
prototype existed. Review regressions also failed before their fixes. The suite
contains no skipped or excluded inventory entries.

The exploration does not claim production-ready support for every listed design
scenario. The precise unsupported cases above and the QA results below constrain
the recommendation. Implementation is tracked separately:

- `bylaw-contract-implement-explicit-function-selection`: minimal core option and
  early built-in filtering, including custom-check behavior and cleanup.
- `bylaw-contract-resolve-diff-source-mapping`: compiler-aware source identity,
  supported subset, lexical/type/generated-code limitations and independent oracles.
- `bylaw-contract-implement-formatter-diff-scope`: environment/Git integration,
  exactly one observer/test run, source matching and reliable failure propagation;
  blocked by the two preceding tasks.

`bylaw-contract-explore-pr-diff-cli` consumes this recommendation. A separate CLI
is not needed to complete any of those three tasks.

## Reproducing the experiment

From the repository root, run the ordinary acceptance suite and quality gate:

```sh
(cd packages/bylaw_contract && mix test test/diff_scope_exploration_test.exs)
scripts/qa.sh
```

The external runner expects Linux `/usr/bin/time`, Python 3, Elixir 1.20.2 and a
supported OTP runtime. Compile `bylaw_contract` in `MIX_ENV=test`; prepare clean,
independent checkouts named `ecto`, `phoenix` and `flame` beneath one caller-owned
directory at the exact pins in `run.py`, with their dependencies fetched and normal
test builds available. It injects the compiled Bylaw path into a diagnostic
formatter; consumer source, dependency manifests, tests and concurrency are not
patched. The comparison refs must exist with their history in each checkout.

```sh
python3 packages/bylaw_contract/qa/diff_scope/run.py \
  /path/to/qa-repositories \
  "$PWD/packages/bylaw_contract" \
  /tmp/bylaw-diff-new-results
```

Use a new output directory for each run. The runner performs two serial rounds in
fresh VMs, first disabled/full/diff and then diff/full/disabled, for each project.
Every invocation runs its normal full test suite with seed `922331`, max cases
`28`, original timeouts and the CLI formatter. This is not a test-selection
benchmark. Logs, terminal ETF captures, peak-RSS files and `results.json` remain
in the output directory, including unsuccessful controls. An unsupported or
incomplete result makes the runner exit nonzero even when every test process
exits zero. Inspect those records rather than treating the runner's status as a
test-failure count.

Raw runs live on the session-owned Sprite `bylaw-contract-diff-env`, under
`/tmp/bylaw-diff-final-runs` and the earlier `/tmp/bylaw-diff-runs-v2`. The Sprite
CLI file API was used for JSON transfer, avoiding its independently observed
large-stdout truncation issue. Do not depend on ephemeral Sprite storage for the
summary: the JSON datasets are retained beside this report.

## Validation limits

The local complete repository gate passed on `0139b9f0`, including the normal
contract acceptance tests and all 974 UI tests. That baseline adds only the
bounded-throughput QA artifacts to the final external-run baseline `01e4bb63`;
the production library is identical between them. The full contract package
suite also passed with 188 tests, and all 18 exploration tests passed under an
inherited Git-hook repository environment. Fixture Git commands now isolate
their environment so they cannot act on a hook's parent repository.
Additional isolated probes confirmed explicit errors when Git is absent from
`PATH` and when the requested base and tested head have unrelated histories.

The Sprite root gate completed every Elixir package stage and UI
formatting/build/typecheck, but did not pass browser tests. The initial missing
Chromium system-library failure was resolved by installing its dependencies. A
subsequent run hit repeated unchanged 5000ms browser timeouts and leftover
contexts in `test/browser/playwright.test.ts`; it was deliberately stopped with
SIGTERM (exit 143) once failures cascaded. The log is
`/tmp/bylaw-diff-final-root-qa.log`, linked to the existing
`bylaw-ui-sprite-browser-timeouts` investigation. No timeout, browser-test or UI
source changes were made. The external contract comparisons run separately;
their success cannot be substituted for a successful remote root gate.

Phase timings distinguish Git plus AST selection, compilation of copied check
modules, observer initialization, suite execution, stopping and report rendering.
Metadata loading, type expansion, structural classifier compilation and compiler
instrumentation remain combined in initialization; this experiment does not
isolate their individual costs. Initialization can also move lazy compilation or
module-loading work out of the suite phase, so suite time alone cannot measure
tracing overhead. Full process elapsed time includes diagnostic script loading
and Mix startup, but excludes the final ETF-to-JSON conversion in the final runner.

Memory snapshots are whole-VM totals at initialization boundaries and completion;
Linux peak RSS covers the full command, including runtime and test work. Neither
is a precise library allocation delta or a hard memory bound. Two ordered rounds
are exploratory evidence, not a statistical performance guarantee. Incomplete
full-scope runs cannot support claims about the cost of complete full observation.

`initial-results.json` preserves the earlier 18 controls at `25e0e8a6`, before
the final review fixes and main refresh. Its process elapsed measurement also
included result conversion. Keep that dataset as provenance; use the final
dataset for the reviewed prototype's measurements.

## Final external results

`final-results.json` retains all 18 final controls, run serially on the Sprite
with Elixir 1.20.2, OTP 28.1 and eight online schedulers. Each record includes
Bylaw revision `01e4bb636ae871090d6917b97e07c1bfbe1846fd`, the consumer pin,
command, prototype script SHA-256 hashes, process status and capture validation.
The hashes match the reviewed scripts committed with this report. All three
consumer checkouts remained clean at the recorded pins after the run.

| Project | Tested commit | Comparison base |
| --- | --- | --- |
| Ecto | `11784f821a1bb0eedeee59583e311d836cb39ee1` | `575791db495c87c2c327a6fd552a68bd0ddd4e74` (`HEAD^`) |
| Phoenix | `1e6183e9ebab9994cf6e43d3af445f32664cc10c` | `332a0658a2fa00d87fe59b171f291a96e3b40c7a` (`f267e8b8c^`) |
| FLAME | `2b124f3ffdede8c1f125ce36b237bef1c50940a3` | `27b94dafd874cd9747007205d25ee2d81349de07` (`e9384f7^`) |

Phoenix and FLAME use the parent of their latest source-changing commit because
their tested tips include later changes outside the selected source paths. These
are real committed source changes, not injected consumer fixtures.

Every test process exited zero: each Ecto run passed 1,591 tests/doctests, each
Phoenix run passed 1,087 with 33 excluded, and each FLAME run passed 62. Captured
Phoenix test-event counts are 1,120 because they include the 33 exclusions. The
two unsupported Phoenix runs have error captures instead of test-event captures;
their CLI logs separately confirm the same passing/excluded totals.

| Project | Full observation, both rounds | Diff observation, both rounds |
| --- | --- | --- |
| Ecto | Incomplete at the unchanged 4,096 queue limit | Complete; only `Ecto.Changeset.validate_length/3`, exactly 194 input and structural arity calls |
| Phoenix | Complete | Unsupported changed context in `Phoenix.CodeReloader.Server`; no assessed scope |
| FLAME | Complete | Complete; only `FLAME.FlyBackend.http_post!/3`, retained with zero observed calls |

Ecto's full runs exceeded the queue guard in Typespec/FunctionClauses at
4,125/4,134 and 4,385/5,724 queued messages. Those observations are explicitly
incomplete and their summaries must not be used as complete gap reports. The
selected Ecto function retained one structural clause and five input classes:
four supported, one unsupported, with one supported class missed. No selected
compiler return alternatives were inferable. Unsupported input remains distinct
from a missed supported input.

Phoenix moves private definitions into compile-time conditional context. The
selector refuses to guess their authored-to-compiled mapping. Both formatter
initializations raised, yet both `mix test` processes still exited zero. The
external validator rejected their error captures, demonstrating why a production
failure mechanism requires subprocess acceptance tests.

FLAME retained its selected private function's structural obligation, but its
suite did not call that function. This validates retention, not exercised
coverage, and provides no selected typespec or compiler alternative evidence.
All six FLAME logs also contain `FLAME.Terminator.clean_up_paths/1` cleanup
errors, including both disabled controls. Passing tests do not erase those
errors; they remain part of the existing
`bylaw-qa-flame-terminator-cleanup-errors` investigation, without new attribution.

Every successful observation capture reports one initialization and a stopped
tracer; disabled controls report zero initializations. All selected target
identities are checked before capture. The final runner exited **1**, correctly
rejecting the two incomplete Ecto runs and two unsupported Phoenix runs. The
generic runtime fixture separately exercises actual selected compiler calls,
selection before the default cap, exact child-process counts, unknown outcomes
and repeated restoration; the external selections do not supply that compiler
coverage evidence.

Ranges below are the two retained measurements, with phase units shown explicitly.
Zeros are rounded sub-millisecond or disabled phases. Unsupported Phoenix runs
have no valid observer phase capture; their process time and RSS include tests
that continued without a successfully initialized observer.

| Project / mode | Process s | Selection ms | Copied checks ms | Init ms | Suite s | Stop / report ms | Peak RSS MiB |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ecto / disabled | 9.69–10.70 | 0 | 0 | 0 | 7.86–8.69 | 0 / 0 | 489.6–492.6 |
| ecto / full | 20.24–20.50 | 0 | 0 | 17468–17502 | 0.94–0.98 | 19–24 / 7 | 645.4–649.4 |
| ecto / diff | 11.18–11.58 | 308–340 | 724–767 | 1392–1531 | 6.53–6.74 | 37–40 / 7–9 | 503.7–518.1 |
| phoenix / disabled | 25.78–26.61 | 0 | 0 | 0 | 23.75–24.65 | 0 / 0 | 385.6–399.7 |
| phoenix / full | 30.10–31.01 | 0 | 0 | 7320–7666 | 20.56–21.19 | 62–64 / 30–38 | 430.8–435.9 |
| phoenix / diff | 26.46–26.79 | unsupported | — | — | — | — | 383.4–395.0 |
| flame / disabled | 19.33–19.49 | 0 | 0 | 0 | 17.73–17.74 | 0 / 0 | 202.4–206.2 |
| flame / full | 19.77–19.79 | 0 | 0 | 1130–1171 | 16.86–16.90 | 22–27 / 9–13 | 207.9–215.2 |
| flame / diff | 19.40–19.44 | 54–56 | 425–442 | 136–157 | 17.16–17.23 | 14–16 / 5–7 | 198.1–205.5 |

The measured Ecto initialization narrows substantially, while the complete test
workload remains. Its full-scope control aborts, so this is not a comparison with
complete full observation. FLAME's complete full and diff process ranges are
close and the selected function is uncalled; they do not establish a general
tracing speedup. Selection is useful first as an explicit adoption boundary;
performance claims must remain tied to supported selections and complete runs.
