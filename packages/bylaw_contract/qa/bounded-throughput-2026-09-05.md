# Bounded trace throughput: measured burst limit

The current default trace transport still loses complete observation when arrival bursts exceed consumer service plus queue capacity. This investigation quantifies that limit; it does not fix complete observation of full stress suites. Follow-up `bylaw-contract-prototype-bounded-producer-observation` will evaluate producer-side aggregation, including semantic and resource feasibility before any default change.

## Reproduction and scope

Baseline: Bylaw `01e4bb636ae871090d6917b97e07c1bfbe1846fd`, Elixir 1.20.2 / OTP 29.0.3. No production code or default queue limit changed. The synthetic fixture has two authored clauses and independently known input, return and clause counts. There are 96 fresh-VM trials, each with two start/stop cycles:

- Typespec, FunctionClauses, and both default checks.
- One or eight concurrent producers; 1,024 or 8,192 total calls, divided evenly.
- 16/4,096-byte binaries or lists of 8/256 integers.
- Bursts or pacing with a 5 ms sleep every eight calls per producer.

The external watchdog samples the owned VM's RSS every 100 ms, stops it above 384 MiB, and imposes a 35-second trial deadline. This is a sampled watchdog, not a hard byte bound. Binary byte size and list heap size are different costs; these fixtures do not establish an arbitrary-payload memory guarantee. Tests use one target MFA, so they do not quantify scaling across target counts.

## Results

All 96 processes exited successfully; no watchdog fired. All 192 cycles verified worker, watcher and trace-session cleanup. Sampled peak RSS ranged from 81,760 to 143,072 KiB.

| Total calls | Shape of traffic | Complete cycles | Incomplete cycles |
| --- | --- | ---: | ---: |
| 1,024 | Burst | 48 | 0 |
| 1,024 | Paced | 48 | 0 |
| 8,192 | Burst | 0 | 48 |
| 8,192 | Paced | 48 | 0 |

Every complete cycle matched independently expected call/return counts and exact alternative hits or clause outcomes for the enabled checks. Coverage and report hashes were identical within each of 12 `(checks, total calls, payload family)` groups across producer count, payload size, pacing and repeated cycles. Incomplete cycles retained explicit reasons exceeding the unchanged 4,096-message threshold and suppressed missed-coverage diagnostics.

For 8,192 calls, measured producer completion ranged from 1,092–5,041 microseconds for Typespec bursts, 1,004–6,042 for structural bursts, and 1,864–14,122 for both checks. Paced versions ranged from approximately 0.767 to 6.618 seconds. These are workload timings including observer interaction and possible early abort, not service-rate estimates or a universal maximum throughput.

The relevant constraint is accumulated arrivals minus serviced events. A finite asynchronous queue can overflow during a short burst even when the long-run average rate is manageable. Typespec generates call and return events, while structural observation consumes calls. Pacing here is a diagnostic variable, not a proposed change to consumer tests. Prior no-op and partitioned controls in [the earlier investigation](throughput-investigation-2026-09-05.md) also overflowed, so removing classifier cost alone has not demonstrated a solution.

## Approved external evidence

Existing captures provide meaningfully different workload evidence without repeating expensive unchanged-runtime runs:

- Ecto `11784f821a1bb0eedeee59583e311d836cb39ee1`: 1,591 tests passed; default observation incomplete, Typespec/FunctionClauses queue observations 4,263/4,154 against 4,096.
- Livebook `f18f2035bac89d6c08497f5f2d7e7c4f56e80716`: isolated NodeManager test passed with complete default observation. Earlier full-suite controls remained incomplete even when all 1,511 tests passed.

The Ecto and isolated Livebook captures used Bylaw `08fb5de5`, Elixir 1.20.2 / OTP 29.0.3; exact scope and captured counts are retained in [generic behavior validation](generic-behavior-2026-09-05.md). These are historical observations, not reruns on this branch or evidence that full-suite completeness has improved. No other repository or derived artifact was used.

## Maintained reproducer

From `packages/bylaw_contract`, compile the test build and run with a new output directory:

```sh
MIX_ENV=test mise exec -- mix compile
BYLAW_LIMIT_EBIN="$PWD/_build/test/lib/bylaw_contract/ebin" mise exec -- python3 qa/bounded-throughput-run.py /tmp/bylaw-bounded-throughput-new
```

The runner preserves every trial log and JSON result, including failures, and refuses to reuse an existing output directory. `bounded-throughput-trial.exs` asserts exact counts for complete cycles and explicit overflow/cleanup behavior otherwise. `bounded-throughput-results.json` retains the original 96 rows; the maintained script changes only fixture/output path portability and formatting. Original raw logs are under `/tmp/bylaw-throughput-limit`. The initial smoke test corrected an expected type label to `[integer()]`; no production behavior was changed to make it pass.

This satisfies the investigation's documented-limit route while leaving the substantive transport improvement in the concrete P1 follow-up. Full stress-suite complete observation remains unresolved.

Validation: repository `scripts/qa.sh` passed. The maintained portable fixture passed a two-cycle default-check smoke run (eight producers, 1,024 calls, 256-element lists). `python3 qa/bounded-throughput-verify.py qa/bounded-throughput-results.json` verified all retained rows and cross-cycle hash equality. No production behavior changed, so this investigation adds a diagnostic workload rather than a new behavior acceptance suite.
