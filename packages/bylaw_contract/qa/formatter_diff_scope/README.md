# Formatter diff scope QA

This change connects the existing source selector and explicit MFA observer selection to the ExUnit formatter. Opting into `BYLAW_CONTRACT_DIFF_BASE` compares the reference merge-base with the tested HEAD while running the normal suite once. Explicit `diff_base` wins; `false` disables it. Invalid selection or incomplete scoped observation must produce a nonzero process status without suppressing tests or replacing their existing failure status.

## Reproduction

Run from `packages/bylaw_contract` in the Bylaw task checkout after compiling its test environment. These runs used Elixir 1.20.2 / OTP 29. The consumer projects and their dependencies were already compiled with the compatible toolchain. No consumer source or configuration files were changed.

```sh
mise exec -- elixir qa/formatter_diff_scope/run.exs /tmp/bylaw-compiler-cap/ecto '59d21ee254bdba2fb8b4086449c49cfb4f091029^' lib/ecto/repo/assoc.ex test/ecto/repo_test.exs
mise exec -- elixir qa/formatter_diff_scope/run.exs /tmp/bylaw-reasons.oRUJf0/livebook '2e45f8aca02d2d4f8007881386a9e9aec3b666db^' lib/livebook/utils/time.ex test/livebook/utils/time_test.exs
```

The QA-only driver loads the consumer configuration and runs its existing Mix test task with both formatters. Temporary `prune_code_paths: false` retains the externally compiled Bylaw adapter. It does not add a production CLI or application orchestration API.

| Repository | Tested HEAD | Final result |
| --- | --- | --- |
| Ecto | `11784f821a1bb0eedeee59583e311d836cb39ee1` | 178 tests pass, exit 0; one structural clause, zero observed calls |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | 20 tests pass, exit 0; one typespec function with one call; 14 of 15 clauses selected, 21 arity calls |

These are focused test-file runs, not full repository suites. Both observations completed without unsupported targets or warnings. Ecto's changed private function has no typespec and was not exercised: the retained structural gap is not evidence of behavioral coverage. Final Ecto output is `ecto-final-driver.log`; `ecto-complete.log` records the earlier successful run before the driver added normal configuration loading for Livebook. Livebook's final output is `livebook-complete.log`. Both checkouts were verified clean after QA.

## Retained unsuccessful and intermediate attempts

- `ecto-no-report.log` and `livebook-no-report.log`: tests passed, but Mix pruned the ad-hoc Bylaw code path. No Bylaw report was produced. These are invalid captures, not successful Bylaw QA.
- `unsupported-qa-flag.log`: Mix rejected `--no-prune-code-paths` as a test option, exit 1. The driver now sets the temporary project configuration instead.
- `ecto-typespec-only.log`: valid but zero-target typespec observation; adding the structural check exposes the uncalled private clause.
- `livebook-config-missing.log`: consumer startup failed, exit 1, because the driver omitted configuration loading. The final driver invokes `loadconfig` before `test`.

## Acceptance evidence and limits

The two formatter acceptance files contain 18 real subprocess scenarios, including unset scope, explicit precedence and disablement, empty scope, malformed options, invalid refs and paths, missing Git/history/common ancestry, dirty sources, inherited Git environment isolation, unsupported mapping, modules outside the application, stale compilation and loaded-BEAM mismatch, nested projects, stacked/cumulative/synthetic-merge/rebased histories, incomplete observation, original failure status, and observer cleanup. Instrumented fixture output verifies one suite body and one observer. The original 16-test inventory ran normally; the populated baseline had 15 failures and one full-scope characterization pass before implementation. The final package suite passes all 247 tests.

Source correspondence checks use the current Mix project's compile manifest, committed/current source digests, and persisted/loaded BEAM identity. They do not replay compilation or establish external dependency or configuration equivalence. Cross-application manifest orchestration is outside this adapter. Selection follows the existing source mapper's explicit supported subset and does not claim transitive impact analysis. Ordinary observation gaps remain nonfatal.

The repository-wide `mise exec -- scripts/qa.sh` gate passed, including formatting, compilation with warnings as errors, strict Credo, package tests, documentation generation, and 974 browser tests.
