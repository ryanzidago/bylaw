# Structural classifier startup optimization

Bead: `bylaw-contract-profile-livebook-structural-startup`.
Baseline library: `f5dcc632075ae1a9b0bb6d9413983d78b344432a` (library source identical to the measured `d64593a47a93071014f369e3838f47b9736a133d` ebin).
Candidate StructuralCoverage source SHA-256: `f8d5425418737929d686e307c80820bc51b27ac1356a1a5cee0565ec4f950796`.
Approved Livebook pin: `f18f2035bac89d6c08497f5f2d7e7c4f56e80716`, Elixir 1.20.2 / OTP 29.0.3 on macOS.

## Problem and change

Structural-check initialization was the main cost in the prior paired Livebook investigation. Three direct baseline startup probes separated metadata loading (0.647–0.679 seconds) from shadow compilation (8.228–9.241 seconds). The compiler-pass probe attributed 5.130 seconds to SSA optimization, including 1.320 seconds in dead-code analysis. These are individual compiler-pass diagnostics, not confidence intervals.

The generated shadow previously computed each clause's head match and guard outcome in separate case expressions. The candidate computes the pair together: a successful guarded match returns `{true, true}`; a head-only fallback returns `{true, false}`; a miss returns `{false, false}`. Unguarded clauses need no rejection branch. Guard success already entails a head match. Original clause selection remains separate, so later clauses still receive their own head/guard outcomes even when an earlier clause is selected.

This reduces generated code without disabling compiler optimizations or validators, changing the public API, changing targets, or increasing the trace budget. A separate diagnostic prototype split classifiers into per-function closures; it was slower and used more reported RSS than the joint-outcome prototype, so it was not adopted.

## Paired startup evidence

Three fresh-VM baseline/candidate pairs alternated order, with no other heavy QA owned by this session running concurrently. Metadata and application loading precede the measured shadow phase. Both sides used the same approved checkout and runtime, with compilation already warm and `mix run --no-compile`. Every run returned 355 modules, 280 classifiers, 5,246 clauses, 3,693 arities and zero metadata warnings. Full loaded-metadata hashes match across all six runs.

| Pair | Baseline shadow seconds | Candidate shadow seconds |
| --- | ---: | ---: |
| 1 | 8.460 | 5.396 |
| 2 | 8.231 | 5.400 |
| 3 | 8.585 | 5.306 |

Median shadow startup decreased from 8.460 to 5.396 seconds, about 36%. This measures shadow creation, not full-suite runtime. The first paired baseline had a slower metadata-loading phase than the other trials; all data is retained. Reported peak RSS varied substantially: baseline 961.8–969.3 million bytes, candidate 722.5–942.5 million bytes. These samples do not establish a stable memory reduction or a hard memory bound. BEAM memory measurements in the JSON are phase boundaries, not peaks.

`structural-startup-results.json` retains all six measurements and metadata hashes. `structural-startup.exs` reproduces the phase measurements with explicit `BYLAW_STARTUP_EBIN` and `BYLAW_STARTUP_OUTPUT` paths, run from the approved checkout with `MIX_ENV=test mix run --no-compile`. `/tmp/bylaw-structural-startup` retains raw timed logs and exploratory profiles. Compiler timing used the [documented compiler-default environment mechanism](https://www.erlang.org/doc/apps/compiler/compile.html#module-default-compiler-options) with `ERL_COMPILER_OPTIONS='[time]'` only in a diagnostic process; the library retains its normal compiler options.

## Preservation tests and validation

Four named empty acceptance tests were inventoried and run normally before bodies were added. Their bodies then passed against the unchanged implementation, establishing preservation cases for raised guard BIFs, alternative guards, repeated variables (including integer/float distinctions), and dependent binary sizes. Each case checks the original function result, exact call count, and every clause's head/pass/rejection/selection counters. These tests intentionally preserve existing correct behavior; the repeated timing probes reproduce the performance problem, rather than introducing a flaky wall-clock unit-test threshold.

After the optimization, all 140 package tests and strict Credo passed. Sixteen structural tests also passed on Elixir 1.19.5 / OTP 28.5.0.4; existing older-runtime compiler-inference warnings remain in the log. No source or test behavior in Livebook was edited.

The bounded trace-budget matrix completed 81 fresh-VM trials / 243 cycles under the existing 384 MiB sampled OS-footprint cutoff. All 163 complete cycles retained exact 1,000-call counts and identical coverage/report hashes per check configuration. The remaining 80 cycles explicitly reported incomplete observations; paused low-budget trials always aborted as expected. One low-budget structural cycle completed legitimately with full counts. Running, delayed and paused consumers and repeated cleanup were exercised. The baseline omits the explicit queue option and therefore still uses its default 4096; it is not an unbounded baseline. `structural-semantic-results.json` retains compact results; the full verifier output is `/tmp/bylaw-structural-startup/semantic-results.json`.

Three alternating baseline/candidate pairs also ran the approved Livebook NodeManager test with all three checks enabled. Every run passed and retained a complete observation. Baseline wall times were 13.013/13.129/14.002 seconds; candidate times were 9.992/10.637/10.002 seconds (median reduction about 24%). This is a small isolated test with application-wide initialization, not a full-suite speedup claim. `structural-observation-results.json` retains commands, terminal results, phase times and resource counters.

Full-suite QA used the same seed 922331, max_cases 28, exclusions and all three checks on both sides. In three alternating pairs, two baseline and two candidate runs passed all 1,511 tests (185 excluded). One baseline run failed the Standalone runtime connection timeout; one candidate run failed two tests: Session.Data could not fetch the personal hub, and AppsDashboard still rendered the closed app. An earlier standalone candidate run also failed a NodeManager connection with a child EPMD undefined-function error. These failures remain investigation items; passing repetitions do not erase them or establish that they are unrelated to instrumentation.

All six paired full-suite observations were explicitly incomplete at the unchanged 4096-event budget. They cannot establish complete coverage equality, nor does this startup optimization resolve full-suite observation throughput. `structural-full-suite-results.json` retains all terminal states and timings, with the oversized rendered-HTML exception summarized and raw captures retained under `/tmp/bylaw-structural-startup`. The complete isolated observations and bounded synthetic matrix above establish the narrower preservation evidence.

Repository-wide `scripts/qa.sh` passed (terminal exit 0); full log retained at `/tmp/bylaw-structural-startup/root-qa.log`. Intermittent personal-hub and dashboard failures are tracked in `bylaw-qa-livebook-shared-state-failures`; runtime connection failures in `bylaw-qa-livebook-epmd-startup-race`; complete full-suite observation throughput in `bylaw-contract-recover-complete-qa-observation`.

Ten additional disabled full-suite runs verified that Bylaw.Contract was not loaded. Nine passed all 1,511 tests; one timed out in Intellisense.ElixirTest setup_all waiting 1,500 ms for runtime connection, invalidating 108 tests. `structural-disabled-suite-results.json` retains terminal results. This establishes a runtime-connection failure without instrumentation, not the exact EPMD root cause. None reproduced the personal-hub or dashboard failure.

A separate bounded probe of the approved Livebook storage code, with Bylaw absent and persistence disabled before application startup, performed 200,000 concurrent reads and 2,000 saves of the same personal hub. It observed 2,643 transient missing-hub reads and verified the original hub was present afterwards. Storage deletes the old attributes before inserting their replacements; direct ETS reads can observe that gap. The asynchronous Hub.EditLiveTest also updates and restores this same hub. This reproduces the storage failure mechanism without Bylaw, but does not prove which write overlapped the original failed test. The probe and raw output remain at `/tmp/bylaw-structural-startup/storage-race.exs` and `.log`. The dashboard failure still lacks causal reproduction.

Twenty fresh-VM disabled runs of the original dashboard test (`test/livebook_web/live/apps_dashboard_live_test.exs:13`) all passed; `structural-dashboard-results.json` retains results. The test receives its own `app_closed` subscription message before rendering the view, while PubSub dispatch sends separately to subscribers. This suggests an ordering race but does not establish the cause of the original failure. No upstream tests, sources or concurrency settings were changed. The unresolved failure remains in the follow-up issue and is a validation limitation of this PR.
