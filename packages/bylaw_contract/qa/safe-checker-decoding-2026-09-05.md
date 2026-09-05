# Checker decoding and VM atom state — 2026-09-05

Bead: `bylaw-contract-investigate-safe-checker-decoding`.
Production baseline: `cb3d62893d01bdf243fbcc17f57d1e2af1617475`.
This change adds characterization tests and evidence, not a production fix.

## Finding and decision

A valid compiler checker chunk can contain atoms that do not yet exist in the
reading VM. For example, a function matching `%Structure{} = value` and returning
`value` has an inferred map descriptor containing every struct field. A field
unused by the function need not appear in that function's runtime atom table or
expanded debug information. Loading the target and reading its debug information
therefore does not necessarily create that field atom.

The two-module fixture in `test/compiler_safe_decoding_test.exs` proves that:

- Compilation happens in a separate VM from inspection.
- Loading the fixture application, target, Bylaw decoder, and compiler descriptor
  module leaves the unused field atom absent (`String.to_existing_atom/1` fails).
- Safe decoding rejects the chunk, and Bylaw returns an explicit unsupported
  module, one warning, and no inferred alternatives or rules.
- Loading the struct module makes that field atom exist; the **same chunk bytes**
  then decode with `binary_to_term(chunk, [:safe])`.
- Loading the struct first avoids the rejection. Renaming modules, application,
  and field preserves the result.

Both tests first ran as named empty tests, then passed with bodies against
unchanged production code. No failing production regression is claimed. An
initial test assumption that every decoded format is supported failed on Elixir
1.19; the final tests separately verify its explicit unsupported-format result.

| Compiler/runtime | Checker format | Cold safe decoding | After struct load | Bylaw after struct load |
| --- | --- | --- | --- | --- |
| Elixir 1.20.2 / OTP 29.0.3 | v8 | rejected | succeeds | supported |
| Elixir 1.19.5 / OTP 28.5.0.4 | v3 | rejected | succeeds | explicitly unsupported version |

Safe decoding is working as intended. Creating atoms from checker input or
preloading arbitrary referenced modules would expand the library's behavior and
loading side effects without resolving a proven correctness defect. Keep the
existing conservative unsupported result and inspection timeout. No application
names, atom allowlists, unsafe checker decoder, or public API were added to production. There
is no proposed remediation requiring a second-project compatibility claim.

## Approved external QA

Only the approved Livebook checkout was used, at revision
`f18f2035bac89d6c08497f5f2d7e7c4f56e80716`, compiled with Elixir 1.20.2 / OTP
29.0.3. Its tracked files and lockfile remained clean. These are new measurements;
they do not reconstruct the older formatter VM or attribute every historical
counter difference to one cause.

| Inspection context | Modules | Supported | Safe-decoding rejection | No inferred signatures | Inspection timeout |
| --- | ---: | ---: | ---: | ---: | ---: |
| Fresh `qa/compiler-reasons.exs` | 355 | 273 | 78 | 4 | 0 |
| Same script, `PRELOAD_MODULES=1` | 355 | 277 | 74 | 4 | 0 |
| Initialized application and all-check ExUnit formatter | 355 | 349 | 1 | 4 | 1 |

Preloading the application's module list does not preload all dependency
modules. A diagnostic inspection of the rejected chunks found missing atoms in
all 78 cold rejections. The first was
`Collectable.Livebook.FileSystem.File`: `file_system_id`, `file_system_module`,
and `origin_pid`, all fields defined by `Livebook.FileSystem.File`. Other
examples included Ecto changeset fields, Phoenix socket fields, URI fields, and
Mint connection fields. A temporary ETF parser read atom names as strings; it
did not create atoms or replace safe checker decoding. The small fixture above
is the maintained reproduction, not that diagnostic parser.

The initialized run used `qa/overhead-capture.exs` with all three checks and
`test/livebook/runtime/erl_dist/node_manager_test.exs`, seed 922331 and
`max_cases: 28`. Its terminal capture verified one passing test, no failures,
and complete observation. The remaining safe rejection was
`LivebookWeb.SessionLive.PackageSearchComponent`; `LivebookWeb.Router` exceeded
the existing 100 ms inspection timeout. Both remain unsupported. This is one
isolated test run, not full-suite coverage or a throughput improvement claim.

## Reproduction and validation

From this package directory:

```sh
mise exec -- mix test test/compiler_safe_decoding_test.exs
mise exec elixir@1.19.5-otp-28 erlang@28.5.0.4 -- \
  env MIX_BUILD_PATH=/tmp/bylaw-safe-checker/otp28-build \
  mix test test/compiler_safe_decoding_test.exs
mise exec -- elixir qa/compiler-reasons.exs "$LIVEBOOK_CHECKOUT" livebook
PRELOAD_MODULES=1 mise exec -- \
  elixir qa/compiler-reasons.exs "$LIVEBOOK_CHECKOUT" livebook
```

Both toolchain runs pass both tests (three independent fixture scenarios).
Elixir 1.19 compilation retains existing warnings about unavailable private
compiler descriptor functions; that compiler's checker format remains
unsupported. Tests do not skip either format or relax the decoding guard. During concurrent
pre-push QA, one inspection hit the existing 100 ms timeout and failed the new
test. The final fixture retries only that exact timeout, at most three attempts;
all raw decoding/atom-state assertions and final module outcomes remain strict.
Other failures are not retried. Production timeout behavior is unchanged.

For the initialized run, prepend this package's test ebin, require
`qa/overhead-capture.exs`, and invoke the Livebook test command above with
`--formatter ExUnit.CLIFormatter --formatter BylawOverheadCapture`.
Set `BYLAW_CONTRACT_APPS=livebook`, `BYLAW_OVERHEAD_MODE=all`,
`BYLAW_OVERHEAD_EBIN` to that ebin, and `BYLAW_OVERHEAD_OUTPUT` to a fresh file.
Validate the terminal file with `qa/overhead-result.exs FILE all`.

Session raw artifacts are under `/tmp/bylaw-safe-checker`: `cold-reasons.log`,
`preloaded-reasons.log`, `livebook-missing-atoms.log`, `node-1-candidate.etf`,
`node-1-candidate.log`, and `isolated-observation-pair.json`. The latter records
the exact command, check set, test results, and completeness. These local files
are supplementary; the tests, commands, pins, and counters above are the durable
record.
