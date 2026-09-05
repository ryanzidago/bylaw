# Reject improper tails in proper-list types

At baseline `8adb7e39db8d30ad3d1a0d1fc17f0e552c54aad5`, checking `[1 | :tail]` against `list(integer())` raises from `Enum.map/2`. An `is_list/1` guard accepts the cons cell without validating its tail. Plain `list()` also incorrectly accepts that value, and character-list checks can raise during traversal.

The fix validates the complete list spine before applying proper-list, nonempty-list, list-length boundary or character-list matching. Valid binary-tailed iolists and unconstrained term/any matches retain their existing semantics. The additional validation traverses proper list spines once before existing element matching; no throughput improvement is claimed.

Four runnable empty acceptance tests were followed by failing bodies against unchanged behavior. The tests now pass, including a real Typespec observation that receives and returns an improper list without altering the caller's value or crashing the observer. Its return spec includes an unused alternative so the existing return-alternative observer is exercised. The full package suite passed 192 tests.

## Approved external QA

Candidate: the task branch based on the revision above; Elixir 1.20.2 / OTP 29.0.3. Both use default Typespec and FunctionClauses checks, seed 922331 and max_cases 28, without upstream modifications.

| Approved repository | Revision | Tests | Observation |
| --- | --- | --- | --- |
| Ecto | `11784f821a1bb0eedeee59583e311d836cb39ee1` | Full unit suite: 1,591 passed | Incomplete: Typespec queue 4,150 and FunctionClauses queue 5,984 exceed unchanged limit 4,096 |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | Isolated NodeManager test: 1 passed | Complete: 16 calls, 49 structural arity calls and 5 returns |

Ecto's passing tests do not prove complete observation; this known transport limitation remains unresolved. Captured summaries are in `improper-list-results.json`. Raw command records, terminal ETF captures and logs are under `/tmp/bylaw-improper-qa`; the runner uses the existing generic-behavior capture helper.

The attempted Elixir 1.19.5 / OTP 28.5.0.4 package run was rejected by Mix because current `mix.exs` declares Elixir `~> 1.20`. It is excluded without changing the package requirement or adding compatibility shims.

Tracked issue: `bylaw-contract-reject-improper-list-tails`. The native prototype that exposed this bug remains separate. Another discovered regression, `bylaw-contract-match-falsey-nonempty-lists`, covers the existing incorrect rejection of nonempty lists containing only false/nil and is not part of this patch.

Repository validation: `scripts/qa.sh` passed. The production change strengthens proper-list validation and leaves all existing incomplete-observation guards intact.
