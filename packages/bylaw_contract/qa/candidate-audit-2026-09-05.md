# Individual external-QA candidate audit

This audit reproduces 13 missed candidates across three approved repositories.
One is a confirmed Bylaw compiler-counter defect. Several declared alternatives
were not exercised, and one apparent miss is explained by test inputs outside
the declared type. Passing suites do not establish diagnostic precision.

## Revisions and observation boundary

Bylaw: `418dedb13499150d325da2e05c19a5c632248d0d`. No library implementation
changes were made for this investigation. Source/spec locations below refer to:

| Repository | Pinned revision | Elixir / OTP | Captured suite result | Missed input / declared return / compiler return |
| --- | --- | --- | --- | --- |
| [Phoenix](https://github.com/phoenixframework/phoenix/tree/1e6183e9ebab9994cf6e43d3af445f32664cc10c) | `1e6183e9ebab9994cf6e43d3af445f32664cc10c` | 1.20.2 / 29 | 1,087 passed; 33 excluded | 110 / 9 / 2 |
| [Changelog](https://github.com/thechangelog/changelog.com/tree/3e46efd3773e9c375633d49d9353608f294da15d) | `3e46efd3773e9c375633d49d9353608f294da15d` | 1.18.3 / 27 | 974 passed | 2,052 / 583 / 0 |
| [Livebook](https://github.com/livebook-dev/livebook/tree/f18f2035bac89d6c08497f5f2d7e7c4f56e80716) | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | 1.20.2 / 29 | 1,511 passed; 185 excluded | 926 / 357 / 3 |

All runs used seed 922331, max_cases 28, and the Typespec, FunctionClauses,
and ElixirCompiler checks through `candidate-capture.exs`. The formatter starts
observation after test loading, before test execution; application startup and
previous compilation are outside that interval. Coverage is application-scoped,
not a count of assertions. A zero below is a supported, non-unknown target with
zero runtime hits, not a static inventory count. `calls` and `return_events` are
MFA-wide counters, not target hits. Compiler counters describe instrumented
clause selection, not direct inspection of returned values.

Phoenix excluded `:mix_phx_new`. Livebook excluded tags were
`[python: false, git: true, fly: true, teams_integration: true, unix: false,
k8s: true, erl_docs: false]`. Changelog had no exclusions. Conclusions concern
these configured runs, not excluded tests, other environments, or all possible
background activity. Static specs alone establish target existence, not exercise.

## Individual evidence

Every numbered row is a distinct candidate; full-suite hit count is zero in
all rows. `T input` and `T return` mean the Typespec check. `C return` means
ElixirCompiler. Locations are relative to the pinned repository. Controlled
counts come from separate one-test formatter runs, not the full-suite totals.

| # | Repository; MFA | Check; exact alternative; source/spec | Full-suite MFA events | Upstream evidence and classification |
| --- | --- | --- | --- | --- |
| 1 | Phoenix; `Phoenix.Token.sign/4` | T input; argument 2 `empty`; `lib/phoenix/token.ex:137` | 121 calls | `test/phoenix/token_test.exs:20-101` uses nonempty salts. **Supported alternative not exercised.** Controlled empty-salt calls return binaries and record 2 hits. |
| 2 | Phoenix; `Phoenix.Token.verify/4` | T input; argument 2 `empty`; `lib/phoenix/token.ex:229` | 1,017 calls, 1,017 returns | Token tests use `"id"` or `"not_id"`. **Supported alternative not exercised.** Controlled empty salt records 1 hit. |
| 3 | Phoenix; `Phoenix.Token.verify/4` | T input; argument 3 `empty`; `lib/phoenix/token.ex:229` | 1,017 calls, 1,017 returns | Token tests at lines 41-50 exercise nil, garbage and wrong salt, not an empty binary. **Supported alternative not exercised.** Controlled `verify(key, "", "")` returns `{:error, :invalid}` and records 1 hit. |
| 4 | Phoenix; `Phoenix.Token.sign/4` | T input; argument 4 `multiple`; `lib/phoenix/token.ex:137` | 121 calls | Token tests at lines 82-101 do pass multiple options, but include `signed_at: 0`; `signed_at_opt` at line 113 requires `pos_integer`. **Supported alternative not exercised:** list length alone is insufficient; elements must match. Controlled zero yields no hit; changing it to 1 yields 1 hit. This is an upstream spec/test discrepancy, not a Bylaw matching defect. |
| 5 | Phoenix; `Mix.Tasks.Phx.Gen.Auth.Injector.router_plug_inject/2` | T return; `:already_injected`; `lib/mix/tasks/phx.gen.auth/injector.ex:98` | 4 calls, 4 returns | `test/mix/tasks/phx.gen.auth/injector_test.exs:508-663` exercises three successful insertions and one unable-to-inject result. No repeat insertion in this block. **Supported alternative not exercised.** Idempotence tests for other injector functions do not exercise this MFA. |
| 6 | Phoenix; `Phoenix.Logger.compile_filter/1` | C return; `{:keep, term()}`; `lib/phoenix/logger.ex:164-167` (no handwritten spec) | 1,571 compiler calls | `test/phoenix/logger_test.exs:54-71` explicitly executes keep, including direct `compile_filter({:keep, []})` at line 57. **Bylaw observation defect.** Targeted logger run: 11 passed, same miss. Persisted synthetic fixture confirms false misses and false hits; details below. |
| 7 | Changelog; `Changelog.Github.Pusher.push/2` | T input; argument 2 `empty`; `lib/changelog/github/pusher.ex:4` | 2 calls, 2 returns | `test/changelog/github/pusher_test.exs:13-33` supplies nonempty show notes. **Supported alternative not exercised.** Controlled empty content with mocked Client records 1 hit. |
| 8 | Changelog; `Changelog.Github.Pusher.push/2` | T return; `{:ok, String.t()}`; `lib/changelog/github/pusher.ex:4` | 2 calls, 2 returns | Same tests mock edit/create responses as `%{}` and assert client invocation. Source lines 16-29 requires status 200/201 for success; `%{}` takes error fallback. **Supported alternative not exercised.** Controlled status 201 returns ok and records 1 hit. |
| 9 | Changelog; `Changelog.Github.Issuer.create/2` | T input; argument 2 `empty`; `lib/changelog/github/issuer.ex:4` | 0 calls, 0 returns | `test/changelog/schema/episode/episode_test.exs:138-143` replaces Issuer itself with a mock. It tests the caller, not real Issuer behavior. **Scope limitation.** Controlled real Issuer with only Client mocked records 1 hit. |
| 10 | Changelog; `Changelog.Github.Issuer.create/2` | T return; `{:ok, String.t()}`; `lib/changelog/github/issuer.ex:4` | 0 calls, 0 returns | Same mocked-Issuer test returns ok from replacement code; it does not validate the original function. **Scope limitation.** Controlled Client status 201 lets original Issuer return ok and records 1 hit. |
| 11 | Livebook; `Livebook.Utils.apply_rewind/1` | T input; argument 1 `empty`; `lib/livebook/utils.ex:751` | 583 calls | `test/livebook/utils_test.exs:3` imports doctests; examples at `lib/livebook/utils.ex:741-748` all have nonempty public inputs. Internal recursive empty tails at arity 3 do not exercise arity 1. **Supported alternative not exercised.** Controlled public empty input returns empty and records 1 hit. |
| 12 | Livebook; `Livebook.Utils.node_from_id/1` | T input; argument 1 `empty`; `lib/livebook/utils.ex:116` | 1 call, 1 return | No direct `node_from_id` test found under `test/`; UtilsTest imports doctests but this function has no example. Source rejects decoded values other than 16-byte hashes. **Supported alternative not exercised.** Controlled empty input returns error and records 1 hit. |
| 13 | Livebook; `Livebook.Utils.node_from_id/1` | T return; `:error`; `lib/livebook/utils.ex:116` | 1 call, 1 return | Same source/test inventory. The captured call did not take the error result. **Supported alternative not exercised.** Controlled empty input records 1 error-return hit. |

The controlled Livebook probe also exercises two-element keyword lists in both
arguments of `keyword_deep_merge/2`; both register 1 hit. That check does not
establish what every full-suite keyword list contained and is not counted as
another audited candidate.

## Confirmed compiler defect

Beads: `bylaw-contract-map-normalized-rules-to-source-clauses` (P1), discovered
from `bylaw-contract-audit-qa-missed-candidates`.

Logger has four source clauses: compiled tuple, discard tuple, keep tuple,
and plain input. The captured compiler plan has two normalized rules: one
combines the compiled/discard/plain inputs; the second describes keep.
`Check.ElixirCompiler` uses normalized rule indexes as abstract-code source
clause indexes. Consequently it instruments source positions 1 and 2, although
the keep clause is source position 3. This is not an untested keep branch.

`normalized-clause-probe.exs` persists and loads a synthetic BEAM, then starts
fresh compiler-only observers for three call sets:

| Actual calls and results | Compiler events | Recorded done / keep hits | Unknown? |
| --- | ---: | --- | --- |
| keep -> keep | 0 | 0 / 0 | both true |
| discard -> done | 1 | 0 / 1 | both false |
| done -> done, keep -> keep | 1 | 1 / 0 | both false |

The second row proves a false hit; the third proves a false miss. The helper
uses `:binary.compile_pattern/1` to preserve the same normalization shape as
Logger. An overly simplified helper changes inference and does not reproduce
the problem. The follow-up must verify source-clause mappings, or explicitly
mark ambiguous cases unassessable, while preserving original-code restoration.
This investigation deliberately does not implement that runtime fix.

## Reproduction and retained evidence

Small probes and the capture wrapper are committed beside this report. ETF
captures are local trusted diagnostic files, not portable or untrusted input.
Do not use unsafe term decoding on files from others. Full source snapshots
and large raw dumps are intentionally excluded.

Build the library into an isolated ebin directory with the same Elixir/OTP as
the upstream project. From `packages/bylaw_contract`:

```sh
BYLAW_AUDIT_EBIN=/absolute/temporary/ebin elixir -e '
  File.mkdir_p!(System.fetch_env!("BYLAW_AUDIT_EBIN"))
  {:ok, _, _} = Kernel.ParallelCompiler.compile_to_path(
    Path.wildcard("lib/**/*.ex"), System.fetch_env!("BYLAW_AUDIT_EBIN"),
    return_diagnostics: true)
'
```

From each pinned approved upstream checkout, after fetching dependencies and
compiling its test environment:

```sh
BYLAW_AUDIT_EBIN=/absolute/temporary/ebin \
BYLAW_CONTRACT_APPS=phoenix \
BYLAW_AUDIT_OUTPUT=/absolute/temporary/phoenix-suite.etf \
elixir -pa /absolute/temporary/ebin -r /absolute/bylaw/packages/bylaw_contract/qa/candidate-capture.exs \
  -S mix test --seed 922331 \
  --formatter ExUnit.CLIFormatter --formatter Bylaw.Contract.QA.CandidateCapture
```

Replace application, output and toolchain for Changelog/Livebook. Use
`BYLAW_AUDIT_COMPILER_PLAN=1` only for diagnostic rule inspection; it copies
worker state and is unsuitable for memory/performance measurements. A
successful suite alone is insufficient: verify the capture file exists and
its test states and summary are populated. Mix can remove initial `-pa`
paths; the wrapper explicitly re-adds `BYLAW_AUDIT_EBIN` during initialization.
An earlier Phoenix pass without a capture was discarded as observation evidence.

Copy `<repo>-candidate-probe.exs` to the upstream checkout's
`test/bylaw_candidate_probe_test.exs`, then add that filename after `mix test`
for a separate controlled run. All three controlled runs passed one test each.
Changelog probes mock only the Client; no real GitHub requests are made.
Run the compiler fixture with:

```sh
elixir -pa /absolute/temporary/ebin /absolute/bylaw/packages/bylaw_contract/qa/normalized-clause-probe.exs
```

Changelog used a disposable PostgreSQL 16.12 container, database
`changelog_audit`, user/password `postgres`, host `127.0.0.1`, port `63801`.
Its disposable `config/test.exs` added
`port: String.to_integer(System.get_env("PGPORT", "5432"))` to the Repo config.
Runs supplied `PGPORT`, `DB_HOST`, `DB_NAME`, `DB_USER`, and `DB_PASS`.
The test alias created/migrated the database. Initial connection failures
preceded successful configuration and are not included in coverage evidence.
The native Changelog toolchain was invoked explicitly from Bylaw's directory,
without enabling unrelated tools in Changelog's mise configuration.

Session-local evidence is under `/tmp/bylaw-candidate-audit.gSUPRh`:
`{phoenix,changelog,livebook}-suite.etf`, corresponding inventory logs,
`{phoenix,changelog,livebook}-controlled.etf`, `phoenix-logger.etf`, its
`.compiler-plan`, and `normalized-clause-probe.log`. Full successful logs are
`phoenix-suite-captured.log`, `changelog-suite-captured.log`, and
`livebook-suite.log`. These paths are locators, not durable dependencies;
use the pinned revisions and committed probes to reconstruct evidence.

## Interpretation and limits

The original Changelog label “inference limitation” is not defensible for its
declared-spec misses: compiler inference is unavailable on its Elixir 1.18
runtime, but Typespec still captures calls and returns. Only two handwritten
specs occur in its library; generated HTTP/Ecto APIs contribute many other
targets. Their mere presence does not prove a product test gap. This sample
supports specific unexercised alternatives and mocked-function scope limits.

Phoenix's “adequately tested” label is also unsupported by aggregate pass
counts. The sample found ordinary boundaries, a spec/test mismatch, and a
confirmed Bylaw compiler defect. Livebook similarly has legitimate unexercised
boundaries; this does not establish the validity of every compiler miss.
Current compiler totals differ from the historical report because Bylaw has
changed. Historical and current measurements must remain distinct.

This is a deliberate diagnostic sample, not random sampling or a precision
estimate. It does not classify all candidates, excluded tests, startup-only
functions, or every background process. Prioritize the confirmed compiler
mapping bug before trusting compiler return miss/hit totals. Preserve each
candidate's source label alongside partition labels: “multiple” alone hides
the element-type requirement demonstrated by Phoenix Token.
