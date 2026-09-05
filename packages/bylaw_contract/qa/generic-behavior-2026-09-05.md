# Generic behavior validation — 2026-09-05

Bead: `bylaw-contract-validate-project-compatibility`.
Library baseline: `08fb5de597edf12e765fd8eb4e09762d5f1d5d4c`.
This change adds focused characterization tests and evidence, not a production
fix, framework dependency, or application/repository orchestration API.

## Test inventory and additions

The explicit `start(modules, options)` / `stop` boundary already has substantial
coverage. The following existing suites were inspected before adding tests;
paths are relative to this package's `test/` directory.

| Behavior | Existing evidence and actual assertions |
| --- | --- |
| Local/remote types, bounded specs and unsupported shapes | `spec_observation_test.exs`, `typespec_expansion_test.exs`, `type_expansion_limit_test.exs`: target identities, independent partitions/boundaries, alias bindings, recursive/opaque unknowns, bounded expansion and source locations |
| Authored clauses, defaults and generated code | `structural_coverage_test.exs`, `structural_eliminated_private_test.exs`: exact source clauses, default arities without generated clause obligations, private calls and eliminated-function handling |
| Guards and caller context | `structural_caller_guard_test.exs`, `structural_caller_variable_test.exs`, `structural_joint_outcomes_test.exs`: exact selected/head/guard counts, child caller identity, variable hygiene and alternative guards whose earlier branch raises |
| Body behavior and return counts | `structural_coverage_test.exs`, `return_alternative_observation_test.exs`: shadow code never executes original bodies, repeated return counts, unsupported returns and isolated sessions |
| Check ownership and lifecycle | `check_state_ownership_test.exs`, `check_selection_acceptance_test.exs`: worker-owned state, ordered claims, cleanup after initialization/activation failure, sibling termination and independent observers |
| Complete/incomplete observation | `trace_backlog_acceptance_test.exs`: exact bounded workload counts, paused/running equivalence, queue exhaustion, incomplete summaries with no gap claims, and resource cleanup over repeated complete/incomplete cycles |
| Experimental compiler limits | `compiler_safe_decoding_test.exs`, `compiler_unassessable_reasons_test.exs`, `compiler_cap_acceptance_test.exs`: explicit unsupported formats/decoding, absent metadata, finite cap omissions and unknown semantics |
| Compiler restoration | `compiler_source_clause_mapping_test.exs`: runtime module MD5 changes during instrumentation and equals its original value after stop, with original return behavior restored |
| ExUnit/report boundary | `check_selection_acceptance_test.exs`, `report_colors_acceptance_test.exs`, `migration_acceptance_test.exs`: formatter initialization, explicit options, silent/unknown reports and source-aware diagnostic content |

The gaps addressed by `generic_behavior_acceptance_test.exs` use modules under
`ContractCompatibility`, supplied directly by callers, with no app-specific
registration. Three named empty tests ran before their bodies were implemented.
The final bodies pass against unchanged production behavior; no failing library
regression is claimed.

1. A child calls four authored clauses: normal return, raise, throw, and exit.
   Captured outcomes match the unobserved baseline exactly. Each original body
   sends one marker, with no extra shadow execution. Independent coverage
   expectations are four calls, one normal return, and one selection per clause;
   the unreturned alternative has zero hits. Raise/throw/exit are caught by the
   fixture caller to compare values; this does not claim every crash topology.
2. A protocol dispatches over a struct with a remote type alias. The two authored
   implementation clauses each receive one selection; generated helpers add no
   structural clause obligations. One call uses a default wrapper and one uses
   the full arity: wrapper/full/implementation counts are 1/2/2. The remote
   struct target has two hits; remote mode alternatives have normal=2, quiet=0.
3. Three observation cycles scope only the caller module. The unlisted protocol
   implementation still executes normally but adds no observed arity. Exact
   counts remain stable, and runtime module MD5 and loaded filename stay equal
   to their originals. This uses loaded-code identity, not merely on-disk BEAM
   bytes, which would not prove that active code was unchanged.

## Toolchains and limits

`mix.exs` declares Elixir `~> 1.19`; README requires OTP 27 or newer for isolated
trace sessions. The default checks are Typespec and FunctionClauses. Compiler
inference is experimental and recognizes the tested Elixir 1.20 checker-v8
format; the existing safe-decoding tests explicitly reject checker v3.

- Elixir 1.20.2 / OTP 29.0.3: new tests and full package suite pass.
- Elixir 1.19.5 / OTP 28.5.0.4: 35 focused tests pass, covering the new cases,
  structural coverage, typespec/return observation, safe decoding and backlog
  lifecycle. The final strengthened MD5 cases were also rerun successfully.
  Existing warnings about unavailable private compiler descriptor functions
  remain; this is not a compiler-v3 support claim.

OTP 27 and the first Elixir 1.19 patch release were not exercised here. This is
not an exhaustive support-range or framework matrix. No consumer was upgraded,
backported or shimmed, and no incompatible external repository was needed.
Unselected approved projects receive no compatibility claim from this task.

## Supplemental approved QA

| Project | Pin | Scope | Test result | Default-check observation |
| --- | --- | --- | --- | --- |
| Ecto | `11784f821a1bb0eedeee59583e311d836cb39ee1` | Full default unit suite | 1591 passed (97 doctests, 1494 tests) | Incomplete |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | `test/livebook/runtime/erl_dist/node_manager_test.exs` | 1 passed | Complete |

Both ran on Elixir 1.20.2 / OTP 29.0.3, seed 922331, `max_cases: 28`, with
unchanged tracked checkouts and lockfiles. Both terminal captures contain exactly
Typespec and FunctionClauses. Ecto's compatible tests passed, but Typespec
observed queue 4263 and FunctionClauses queue 4154 exceeded their 4096 limits.
Only 1907 input calls, 502 structural arity calls and 988 returns were retained.
Its summary exposes only incomplete status/reasons, not gap counts. This evidence
was added to `bylaw-contract-recover-complete-qa-observation`; the existing issue
remains unresolved. Passing consumer tests is not complete coverage.

The isolated Livebook run retained 16 input calls, 49 structural arity calls and
5 return events with complete observation. All 355 structural module inspections
were supported. This does not establish full Livebook suite completeness.
`generic-behavior-results.json` preserves statuses, summaries and retained counts.

Prior evidence is reused rather than repeated: `diagnostic-colors-2026-09-05.md`
records actual formatter output on/off runs; `compiler-cap-2026-09-05.md` records
compiler-only full Ecto/Livebook suites and their unsupported states;
`safe-checker-decoding-2026-09-05.md` explains cold/preloaded atom-state failures;
`throughput-investigation-2026-09-05.md` retains unresolved full-suite backlog
limitations. None is treated as proof of framework-wide support.

## Reproduction

From this package:

```sh
mise exec -- mix test
mise exec elixir@1.19.5-otp-28 erlang@28.5.0.4 -- \
  env MIX_BUILD_PATH=/tmp/bylaw-generic-behavior/otp28-build mix test \
  test/generic_behavior_acceptance_test.exs test/structural_coverage_test.exs \
  test/return_alternative_observation_test.exs test/spec_observation_test.exs \
  test/compiler_safe_decoding_test.exs test/trace_backlog_acceptance_test.exs
```

External captures reuse `qa/overhead-capture.exs` with a temporary `default` mode
selecting only Typespec and FunctionClauses. The formatter delegates normal
observation-window/test events and captures terminal coverage at suite completion.
The command is `elixir -pa EBIN -r CAPTURE -S mix test [TEST_PATH] --seed 922331
--max-cases 28 --formatter ExUnit.CLIFormatter --formatter BylawOverheadCapture`,
with `BYLAW_CONTRACT_APPS` set to the loaded app and `BYLAW_OVERHEAD_MODE=default`.
Set `BYLAW_OVERHEAD_EBIN` and a fresh `BYLAW_OVERHEAD_OUTPUT` path. Ecto uses no
TEST_PATH; Livebook uses the isolated path above.

Raw scripts, exact commands, logs and terminal captures are under
`/tmp/bylaw-generic-behavior`, including `run.py`, `capture.exs`, `runs.json`,
`ecto-default.etf`, `livebook-default.etf`, `otp28-tests.log` and `results.json`.
Only Bylaw, approved QA repositories, synthetic fixtures and installed toolchains
were accessed. No production fix or independent new defect was established.
