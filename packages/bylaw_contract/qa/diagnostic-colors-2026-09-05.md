# Diagnostic colors — 2026-09-05

Bead: `bylaw-contract-add-colored-output`. Baseline: `7a4ff2aa`.

Human reporting now styles miss markers, categories and exact missed targets
red, source locations cyan, and supporting specs dim. Explanatory prose stays
neutral. A structural clause's source is its exact missed target, so it is red.
Every styled segment resets. Wording, ordering, silent success, unknown-target
filtering, summary output, and coverage data are preserved.

`print_report(coverage, device, colors: boolean)` adds an optional third argument;
existing one- and two-argument calls remain available. The default follows
`IO.ANSI.enabled?/0`. The formatter honors ExUnit's `colors: [enabled: boolean]`
with the same fallback, matching the installed ExUnit CLI formatter's semantics.
Explicit true forces color; false disables it. No new application configuration
or dependency is introduced.

## Acceptance

Six named empty tests ran before bodies were implemented. All six then failed
against the unchanged API; the implementation makes them pass. They cover all
finding categories, stripped-output parity, color forcing/disabling, runtime
ANSI defaults, formatter propagation, silent and unknown-only reports, summary
preservation, and resets. Existing plain-text tests now request `colors: false`
so their assertions remain stable in ANSI-enabled terminals.

The package suite passes (158 tests) on Elixir 1.20.2 / OTP 29.0.3, and strict
Credo passes. Nine focused color/report tests also pass on Elixir 1.19.5 / OTP
28.5.0.4; existing private compiler API warnings remain on that older toolchain.
This rendering change does not extend compiler-format support.

## Approved external QA

Livebook revision `f18f2035bac89d6c08497f5f2d7e7c4f56e80716`, compiled with
Elixir 1.20.2 / OTP 29.0.3, was used without tracked edits. Three independent
runs of `test/livebook/runtime/erl_dist/node_manager_test.exs`, seed 922331 and
`max_cases: 28`, passed with the actual Bylaw ExUnit formatter and its default
typespec/structural checks. Each emitted completed gap reports, without an
initialization error or incomplete-observation diagnostic.

| Run | CLI flag | Result | ANSI in report |
| --- | --- | --- | --- |
| Baseline | `--no-color` | one test passed | no |
| Candidate | `--no-color` | one test passed | no |
| Candidate | `--color` | one test passed | yes |

Candidate color-on output, stripped of ANSI, exactly equals candidate color-off
output. The baseline observation differed by one missing
`Livebook.Intellisense.clear_cache/1` input (`node()`); that runtime difference
is retained, not attributed to styling or filtered out to claim identical runs.

To isolate rendering from runtime activity, both renderers also printed the
same saved complete Livebook coverage from the checker-decoding investigation.
Their plain output was byte-identical: 2,191,912 bytes, SHA-256
`62e6124e45ab0fa0f9fff498d2fa2d51fec0cb8345ca62730611c38498e26365`.
The first snapshot attempt used a Latin-1 file device and failed in both
versions at the existing Unicode miss marker. Repeating with UTF-8 devices
completed successfully; partial output was not used as evidence.

Actual ANSI report segments were rendered and visually reviewed with light and
dark terminal palettes. Locations, targets and prose remained readable, and
following text returned to neutral. Exact shades and dim intensity remain
terminal choices. This is an isolated-test integration check, not a full-suite
coverage or performance claim.

## Reproduction

From this package, run `mise exec -- mix test`. For the older runtime:

```sh
mise exec elixir@1.19.5-otp-28 erlang@28.5.0.4 -- \
  env MIX_BUILD_PATH=/tmp/bylaw-contract-colors/otp28-build \
  mix test test/report_colors_acceptance_test.exs test/report_test.exs
```

External command, from the approved checkout:

```sh
BYLAW_CONTRACT_APPS=livebook elixir -r LOADER -S mix test \
  test/livebook/runtime/erl_dist/node_manager_test.exs \
  --seed 922331 --max-cases 28 --no-color \
  --formatter ExUnit.CLIFormatter --formatter ColorQAFormatter
```

Repeat with `--color`. The loader delegates `init/1`, `handle_cast/2` and
`terminate/2` to the actual `Bylaw.Contract.ExUnitFormatter`, restoring only the
selected Bylaw ebin inside `init/1` after Mix resets dependency paths.

Session raw commands/results are in `/tmp/bylaw-contract-colors/run-qa.py` and
`qa-results.json`; logs/reports use the `baseline-off`, `candidate-off`, and
`candidate-on` prefixes. Snapshot comparison uses `render-snapshot.exs` and the
two `*-snapshot.txt` files. `light.png` and `dark.png` preserve visual previews.
No unapproved repositories or their artifacts were used.
