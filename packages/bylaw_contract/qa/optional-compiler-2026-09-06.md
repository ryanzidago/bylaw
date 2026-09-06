# Optional compiler inference and Elixir compatibility

Beads: `bylaw-contract-optional-compiler-inference`.
Baseline: `eabcefe4cee376372adc99d497561db2388b40d9`.

The package-wide Elixir 1.20 minimum prevented Elixir 1.19 consumers from using
the default Typespec and FunctionClauses checks. The user requested restoring
1.19 support while keeping the experimental compiler check optional.

The package now declares `~> 1.19`. The two internal modules that use 1.20
compiler helpers conditionally compile their actual implementations on
`~> 1.20`. Older builds retain an unavailable inference adapter and conservative
empty clause mapping; their BEAM imports contain no `Module.Types.Descr` calls.
No warning-suppression attributes, application configuration or new public
check-list API are introduced.

Explicit compiler opt-in on native 1.19 BEAMs preserves unsupported checker
diagnostics in `compiler_modules` and `compiler_warnings`. It produces no false
compiler gaps and does not disable other selected checks. Safe term decoding,
checker-format eligibility, observation limits and code restoration are
unchanged. The shared loader dispatches dynamically to the adapter because
the older implementation only returns errors; a static call makes Elixir 1.19
warn that the common success branch cannot match.

## Validation

Four named empty acceptance tests ran first. With bodies added, the minimum
version assertion failed against the unchanged package; the other three tests
established existing default-check, inference and cleanup behavior on 1.20.
The tests now run on both toolchains, asserting native supported or unsupported
inference results and exact preservation of default-check coverage.

| Runtime | Verification | Result |
| --- | --- | --- |
| Elixir 1.19.5 / OTP 28.5.0.4 | Fresh production build, `--warnings-as-errors` | Passed |
| Elixir 1.19.5 / OTP 28.5.0.4 | New compatibility tests plus safe-decoding tests | 6 passed |
| Elixir 1.19.5 / OTP 28.5.0.4 | Default checks, types, structural coverage, selection, formatter/diff integration, ownership, reporting and queue behavior | 142 passed |
| Elixir 1.20.0 / OTP 28.5.0.4 | Fresh production build, `--warnings-as-errors` | Passed |
| Elixir 1.20.0 / OTP 28.5.0.4 | Compatibility, compiler inference and source-clause mapping | 31 passed |
| Elixir 1.20.2 / OTP 29.0.3 | Repository-wide `scripts/qa.sh` | Passed, including 974 UI tests |

The 1.19 run is a selected compatibility suite, not the entire development
suite. Tests requiring actual 1.20 inference remain in the normal 1.20 suite.
The partition measurement harness also retains its 1.20 fixture/toolchain and
fixed build-path assumptions; its six tests run in the normal repository QA.
The first 1.19 selection included that harness and its setup was invalidated
before observation by the fixture's declared version. This is retained as a QA
tooling exclusion, not counted as a passing compatibility test. Elixir 1.19.0
and OTP 27 were not exercised in this change.

The first broad 1.19 run also exposed a formatter fixture still declaring 1.20,
one safety test expecting a compiler diagnostic available only on 1.20, and
formatter assertions using the newer ExUnit success-line spelling. The fixture
minimum and assertions now support both versions while preserving exact success
counts, error statuses and safety assertions. No test is skipped or tagged out
of the normal suite. Existing deliberate unused-function fixtures still emit
their expected warnings; the library's production build is warning-free.

## Retained failures and reproduction

The unchanged package was rejected by Mix on 1.19. An isolated baseline copy
with only its minimum version relaxed failed strict compilation on
`Module.Types.Descr.upper_bound/1` and `bitstring/0`. The first gated candidate
then exposed the static-call success-branch warning described above. Both
failures remain alongside the passing clean build. The first repository QA
run found two missing typespec argument names in the new fallback functions;
those annotations were corrected before the final run.

Raw logs and exact command arrays are under
`/tmp/bylaw-optional-compiler-20260906`. From `packages/bylaw_contract`, with
the named toolchains and ordinary development dependencies installed:

```sh
MIX_ENV=prod MIX_BUILD_PATH=/tmp/bylaw-contract-119-prod \
  mise exec elixir@1.19.5-otp-28 erlang@28.5.0.4 -- mix compile --warnings-as-errors
MIX_BUILD_PATH=/tmp/bylaw-contract-119-test \
  mise exec elixir@1.19.5-otp-28 erlang@28.5.0.4 -- mix test \
  test/optional_compiler_inference_test.exs test/compiler_safe_decoding_test.exs
```

The user's observation about limited inference yield agrees with the historical
[compiler-cap study](compiler-cap-2026-09-05.md): Ecto had zero assessable
alternatives; Livebook had five, of which four were observed and one missed.
Those compiler-only measurements supplied no earlier-check claims and are not
new measurements or a general estimate of incremental findings. They do not
make an experimental integration a prerequisite for the default checks.
