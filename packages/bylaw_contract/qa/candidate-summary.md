# External QA candidate summary

These are historical aggregate candidate counts from the original full-suite runs.
See [the individual candidate audit](candidate-audit-2026-09-05.md) for newer
measurements, source/test evidence, and a confirmed compiler-counter defect. A missed
candidate means a supported contract alternative had zero observed test hits;
it is not automatically a defect. Unsupported compiler/module counts are
inference limitations and are excluded from actionable-gap counts.

| Repository | Missed inputs | Missed declared returns | Missed compiler returns | Classification |
| --- | ---: | ---: | ---: | --- |
| Plausible | 1,358 | 261 | 2 | not individually classified |
| Changelog | 2,052 | 583 | 0 | not individually classified |
| Realtime | 962 | 180 | 0 | not individually classified |
| Phoenix | 110 | 9 | 2 | individual audit found a Bylaw compiler defect |
| Phoenix LiveView | not captured reliably | not captured reliably | not captured reliably | external timing failures |
| FLAME | 12 | 3 | not assessable | not individually classified |
| Livebook | 926 | 357 | 2 | not individually classified |
| Ecto | 391 | 85 | 0 | not individually classified |
| Vutuv | 447 | 144 | 0 | not individually classified |

The original aggregate review did not confirm a Bylaw defect. The subsequent
individual audit confirmed false compiler hits and misses and filed
`bylaw-contract-map-normalized-rules-to-source-clauses`. Changelog samples
include unexercised declared alternatives and mocked-function scope limits;
compiler incompatibility does not explain its declared-spec misses. The original
commands, pinned commits, toolchains, test counts, failures, and raw summary
metrics are in `external-qa-2026-09-05.md`.
