# Eliminated private-function regression QA

Beads: `bylaw-contract-handle-compiler-eliminated-private-functions`.
Base revision: `7b93bcd47806c2acc72ef3e5da16fe828342f04b`.

An unused private definition remains in Elixir debug definitions but is absent
from reconstructed BEAM abstract functions. Previously that absence discarded
all structural obligations in the module, including callable public clauses.
Elixir explicitly records these definitions in its `unreachable` metadata.
The fix omits a missing definition only when it is private and present in that
set. Missing public functions still invalidate the module. Metadata is validated
before abstract reconstruction so a malformed unreachable field cannot trigger
a backend exception before validation.

The persisted-BEAM regression file is
`test/structural_eliminated_private_test.exs`. It compiles each fixture with
debug information, saves the BEAM, unloads/reloads it from disk, and cleans up
its temporary code path and files. Fixtures cover ordinary unused private code,
private overrides with and without `super`, reachable private overrides,
equivalence of surviving public obligations, missing public functions, malformed
metadata, and runtime observation of both public clauses with no phantom private
miss. Four acceptance tests failed against unchanged behavior; the reachable
private and negative controls passed. The stronger malformed-field control also
proved the need to validate before reconstructing abstract code.

| Validation | Result |
| --- | --- |
| Elixir 1.20.2 / OTP 29.0.3, complete package suite | 126 passed |
| Strict Credo | Clean |
| Elixir 1.20.2 / OTP 29.0.3, focused structural suites | 12 passed |
| Elixir 1.19.5 / OTP 28.3, focused structural suites | 12 passed |
| Approved Phoenix `1e6183e9ebab9994cf6e43d3af445f32664cc10c` | 1,087 passed; 33 excluded |

Run the focused tests from `packages/bylaw_contract`:

```sh
mise exec -- mix test test/structural_eliminated_private_test.exs test/structural_coverage_test.exs
MIX_BUILD_PATH=/absolute/temporary/build-otp28 \
  mise exec erlang@28.3 elixir@1.19.5-otp-28 -- \
  mix test test/structural_eliminated_private_test.exs test/structural_coverage_test.exs
```

The unused-function compiler warnings are expected evidence from the fixtures.
Phoenix used all three checks through `qa/candidate-capture.exs`, seed 922331,
max_cases 28, and the isolated ebin procedure in the individual candidate audit.
Its source/tests were unchanged. This is compatibility QA; the synthetic
fixtures provide the direct regression evidence. No unapproved repository was
accessed. Phoenix was rerun after the final metadata-read ordering hardening;
the final focused matrix and `scripts/qa.sh` also passed.

Session-local logs: `/tmp/bylaw-eliminated-private-{red,green,suite,credo}.log`,
`/tmp/bylaw-eliminated-private-otp28-final.log`, and
`/tmp/bylaw-eliminated-private-qa.wGgsmf/phoenix-final.{log,etf}`. These are temporary
locators; the committed tests and pinned revision make the work reproducible.
