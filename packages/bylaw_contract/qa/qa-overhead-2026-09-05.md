# Controlled QA overhead and timing-failure investigation

Bead: `bylaw-contract-investigate-qa-overhead`. The original QA log attributed timing failures to external causes without paired controls. This investigation corrects those claims and retains terminal results for controlled disabled/enabled runs on the three affected approved repositories. Historical failure attribution remains unresolved where the exact failure did not reproduce.

## Revisions and scope

Bylaw: `e54b873f4b9d693faa7eb014870a3f0ee4e2a822` (PR #275). The OTP 29 ebin was built from `d64593a47a93071014f369e3838f47b9736a133d`; the library source diff is empty. The OTP 28 ebin was compiled from this worktree at the merge revision. No library runtime behavior changes are part of this investigation. The historical Bylaw build was `1e42a14ca3eadec14fa0442f04b1f9101c83763d`, another limitation on retrospective attribution.

| Approved repository | Pinned revision | Runtime used | Scope |
| --- | --- | --- | --- |
| Livebook | `f18f2035bac89d6c08497f5f2d7e7c4f56e80716` | Elixir 1.20.2 / OTP 29.0.3 | NodeManager test; full suite |
| Phoenix LiveView | `8015b9c09a5606f5f3e7204a64ecf9cc28c5b683` | Elixir 1.20.2 / OTP 29.0.3 | StreamAsync and LiveReload files; full suite |
| Realtime | `21ce9acb5a171b07d7494a80fe0a3f2d008f5710` | Native Elixir 1.19.5 / OTP 28.5.0.4 | GenRpcBadTcpTest; related GenRPC/PubSub/metrics tests |

LiveView previously ran on Elixir 1.18.3 / OTP 27.3.3. Current Bylaw requires Elixir `~> 1.19`, so these supported-runtime pairs do not reproduce that historical toolchain. Realtime uses its pinned mise versions. Its compiler-check support differs from Elixir 1.20; complete trace transport does not imply every target is assessable.

## Method

The core matrix has 18 pairs / 36 fresh-VM trials: three pairs for each scope above, alternating disabled/enabled, enabled/disabled, disabled/enabled. Every pair keeps revision, dependencies, runtime, test selection, seed (922331), concurrency, services and exclusions fixed. Livebook/LiveView use max_cases 28; Realtime uses 4. No upstream source/test edits or timeout increases were used. Heavy trials ran serially with no other heavy QA owned by this session.

Dependency and test compilation completed before timing. Caches were warm but not reset between runs. The process interval includes VM/application startup, formatter initialization, tests, drain, capture and shutdown. Phase measurements use formatter event boundaries; stop excludes ETF writing. macOS `/usr/bin/time -l` resource counters are reported as emitted, not a sampled sum of the whole process tree or a leak measurement.

Disabled controls omit Bylaw code paths and verify that no Bylaw.Contract modules loaded. Enabled trials select Typespec, FunctionClauses and ElixirCompiler with the unchanged default 4096 queue threshold. The diagnostics retain test failures, exit status, options, phase times and coverage. A passing exit alone is insufficient: the final ETF, expected mode and exact configured check set must validate. An exploratory formatter attempt without restoring the ebin after Mix changed paths produced no enabled ETF; those attempts are excluded.

## Core results

Wall times are medians with observed min/max ranges, in seconds. Three trials per side describe this sample, not a confidence interval. Incomplete observations cannot estimate the cost of complete instrumentation.

| Project | Scope | Disabled seconds | All checks seconds | Enabled observation |
| --- | --- | ---: | ---: | --- |
| Livebook | node | 1.073 [1.031, 1.147] | 13.158 [13.058, 13.274] | complete |
| Livebook | full | 9.527 [9.449, 9.545] | 20.399 [20.049, 20.580] | incomplete |
| liveview | focused | 0.914 [0.878, 1.157] | 8.696 [8.668, 8.704] | incomplete |
| liveview | full | 9.002 [8.923, 9.091] | 16.764 [16.704, 16.949] | incomplete |
| realtime | focused | 8.443 [8.336, 8.474] | 13.149 [13.055, 13.268] | complete |
| realtime | broad | 38.307 [37.948, 38.565] | 43.054 [42.566, 43.153] | complete |

Livebook isolated: all six runs passed the one NodeManager test; enabled observations were complete. Full suite: all disabled runs passed 1,511 tests (185 excluded). Enabled run one passed 1,403 with 108 invalid; runs two and three passed 1,511. All full enabled observations were incomplete. Typespec/FunctionClauses observed queue lengths were 4202/4542, 4180/4585 and 4180/4216 against 4096.

LiveView focused: enabled runs passed all 23 tests; disabled runs one and three passed 23, while run two passed 22 and failed LiveReload rendering. All six full runs passed 1,528 tests. Every enabled focused/full capture was incomplete. Median enabled initialization was 7.842 seconds focused and 8.774 seconds full.

Realtime: all six focused runs passed five tests, and all six broader runs passed 93 tests. Every enabled observation was complete. Median enabled initialization was 4.720 seconds focused and 4.884 seconds broader. The first focused enabled capture recorded 103 Typespec calls across 20 MFAs and 985 structural calls across 100 MFAs; compiler calls were zero on this older runtime. The broader selection is not the full historical 2,196-test suite.

## Repeated check isolation

Nine additional pairs / 18 trials isolated Typespec, FunctionClauses and ElixirCompiler on the same Livebook NodeManager test. Each mode used three alternating pairs with a disabled control, unchanged seed/concurrency and a fresh VM. All tests passed and every enabled observation completed. These trials follow the same method as the core matrix.

| Enabled check | Disabled wall median [range], seconds | Enabled wall median [range], seconds | Init median [range], seconds | Suite median, seconds |
| --- | ---: | ---: | ---: | ---: |
| typespec | 1.157 [1.097, 1.193] | 2.066 [2.004, 2.085] | 0.920 [0.899, 0.926] | 0.274 |
| structural | 1.125 [1.102, 1.143] | 11.780 [11.736, 12.149] | 10.649 [10.571, 11.006] | 0.275 |
| compiler | 1.097 [1.091, 1.154] | 1.886 [1.880, 1.896] | 0.733 [0.725, 0.740] | 0.277 |

The structural-only elapsed increase is concentrated in initialization. `FunctionClauses.init/3` loads structural metadata and compiles a classifier shadow through `StructuralCoverage.start_shadow/1`; these measurements do not yet separate those internal costs. The profiling follow-up owns that attribution and any behavior-preserving optimization. Per-trial phase times and resource counters are retained in `qa-overhead-livebook-isolation.json`.

## Failure attribution

| Historical failure | New retained evidence | Classification |
| --- | --- | --- |
| Livebook NodeManager runtime-connect timeout | Isolated pairs passed. One enabled full run instead hit EPMD `start_link/0` undef and invalidated Intellisense setup. Other full runs passed. | Unresolved; the exact historical timeout did not reproduce. |
| LiveView StreamAsync exit timeout | Focused and full pairs did not reproduce it on the supported current runtime. | Unresolved; historical runtime differs. |
| LiveView custom-reloader timeout | A disabled focused run rendered Version 1 instead of Version 2 at `live_reload_test.exs:48`, in a neighboring LiveReload test. | Unresolved for the historical timeout; the neighboring render failure reproduced without Bylaw. |
| Realtime GenRpcBadTcpTest peer-start timeout | All focused and related-suite pairs passed on the native runtime. | Unresolved; non-reproduction in these scopes is not proof of no effect in the full suite. |

The Livebook enabled failure logged `Livebook.Runtime.EPMD.start_link/0` as undefined in a child VM, followed by a 1500 ms receive failure at `test/livebook/intellisense/elixir_test.exs:2402`. At the pin, `standalone.ex:221` removes and recreates the shared `Config.tmp_path()/epmd` directory for every connection before writing the EPMD BEAM; multiple connecting test modules are async. This is a concrete race hypothesis, not a minimized causal reproduction. `bylaw-qa-livebook-epmd-startup-race` owns minimization and attribution. No Bylaw defect is declared from that single enabled association.

## Reproduction and retained evidence

The compact `qa-overhead-livebook-pairs.json`, `qa-overhead-liveview-{focused,full}.json` and `qa-overhead-realtime-{focused,broad}.json` retain per-trial commands, results, timings and resource counters. Raw logs/ETFs and exact serial runners remain under `/tmp/bylaw-overhead-pairs`. Initial Livebook trials used `candidate-capture.exs`; later trials use the common `overhead-capture.exs` and `overhead-result.exs`.

Run from the Bylaw package under the chosen toolchain. The runner requires a clean approved checkout at the exact pin and a fresh output directory. It alternates three serial pairs, preserves failed runs and validates terminal captures. A 900-second timeout kills only its owned process group. Select a check with `--enabled-mode typespec`, `structural`, or `compiler`; the default is `all`.

```sh
python3 qa/run-overhead-pairs.py liveview "$LIVEVIEW_CHECKOUT" "$BYLAW_EBIN" \
  "$FRESH_OUTPUT" --selection \
  test/phoenix_live_view/integrations/stream_async_test.exs \
  test/phoenix_live_view/integrations/live_reload_test.exs
```

For full Livebook/LiveView suites, omit `--selection`. Realtime broader selections are listed verbatim in its JSON commands. The original Livebook baseline helper registered `System.at_exit/1` and rejected any loaded module whose atom name starts with `Elixir.Bylaw.Contract`; enabled runs set `BYLAW_CONTRACT_APPS=livebook`, `BYLAW_AUDIT_EBIN`, and a fresh `BYLAW_AUDIT_OUTPUT` for `candidate-capture.exs`. The common runner now supplies the equivalent explicit mode/environment setup.

## Realtime services

The default upstream Docker test backend can reap other abandoned test containers. This investigation used its documented external backend with four independent tenant databases, matching the default concurrency of four. Both paired sides used this topology; the historical topology may differ. Five new compose projects used upstream files, initialization scripts and `supabase/postgres:17.6.1.166`:

| Project | Role | Assigned host port |
| --- | --- | ---: |
| bylaw-overhead-rt-registry | Registry PostgreSQL | 55012 |
| bylaw-overhead-rt-tenant-1 | Tenant PostgreSQL | 55013 |
| bylaw-overhead-rt-tenant-2 | Tenant PostgreSQL | 55014 |
| bylaw-overhead-rt-tenant-3 | Tenant PostgreSQL | 55015 |
| bylaw-overhead-rt-tenant-4 | Tenant PostgreSQL | 55016 |

The fixed environment set `DB_PORT=55012`, `TEST_RUN=bylaw_overhead`, `TEST_PORT=4102`, `USE_EXTERNAL_TENANT_DB=true` and `EXTERNAL_TENANT_DB_PORTS=55013,55014,55015,55016`, plus the pinned mise public development settings. Endpoint/peer port ranges were checked free. Registry creation and migrations ran before timing via `MIX_ENV=test mix test.setup`. Health and ownership labels were checked before tests.

All five owned database containers are stopped and their volumes preserved for recovery. `realtime-services.json` records IDs/compose commands, `realtime-env.json` records settings, and `realtime-cleanup.json` records verified stopped IDs. No pre-existing service or database was changed.

## Validation and follow-up

Terminal validation accepted valid captures and rejected missing captures and mode mismatches. The Elixir diagnostics passed formatting checks. All 18 additional isolation trials passed with complete observations. `scripts/qa.sh` passed, including 974 UI tests with zero failures. The two newly created clean LiveView and Realtime clones were moved into recoverable Trash locations, recorded with the owned service IDs in `qa-overhead-cleanup.json`; the pre-existing Livebook checkout was left unchanged. Raw logs and captures remain available outside those clones.

`bylaw-contract-profile-livebook-structural-startup` owns profiling and any tested startup optimization. `bylaw-qa-livebook-epmd-startup-race` owns the child startup race investigation. Follow-up throughput work must retain complete observations within a deliberate budget; aborted runs cannot be credited as equivalent-workload speedups.
