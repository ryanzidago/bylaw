# External QA candidate summary

These are aggregate candidate counts from the full-suite runs. A missed
candidate means a supported contract alternative had zero observed test hits;
it is not automatically a defect. Unsupported compiler/module counts are
inference limitations and are excluded from actionable-gap counts.

| Repository | Missed inputs | Missed declared returns | Missed compiler returns | Classification |
| --- | ---: | ---: | ---: | --- |
| Plausible | 1,358 | 261 | 2 | inference limitation / review needed |
| Changelog | 2,052 | 583 | 0 | inference limitation |
| Realtime | 962 | 180 | 0 | inference limitation |
| Phoenix | 110 | 9 | 2 | adequately tested / review needed |
| Phoenix LiveView | not captured reliably | not captured reliably | not captured reliably | external timing failures |
| FLAME | 12 | 3 | not assessable | adequately tested / inference limitation |
| Livebook | 926 | 357 | 2 | inference limitation / review needed |
| Ecto | 391 | 85 | 0 | inference limitation |
| Vutuv | 447 | 144 | 0 | inference limitation |

No candidate was confirmed as an actionable Bylaw defect, so no Beads issue was
created. The full commands, pinned commits, toolchains, test counts, failures,
and raw summary metrics are in `external-qa-2026-09-05.md`.
