# bylaw-ui

`bylaw-ui` turns objective rendered layout relationships into executable,
machine-readable checks. It measures elements identified by exact `data-testid`
values in Playwright and evaluates their geometry without screenshot analysis.

## Install

```sh
npm install bylaw-ui playwright-core
```

Chromium is the verified V1 browser target. Install the browser build matching
your Playwright version:

```sh
npx playwright-core install chromium
```

## Use

Import rules and reporting from the package root. Import the browser integration
from the separate Playwright entrypoint.

```ts
import {
  align,
  assertLayout,
  checkLayout,
  inside,
  leftOf,
  overlap,
} from "bylaw-ui";
import { playwright } from "bylaw-ui/playwright";

const report = await checkLayout({
  adapter: playwright(page),
  rules: [
    align("avatar-icon", "timeline", "centerY", {
      tolerancePx: 1,
    }),
    leftOf("avatar-icon", "timeline", {
      gap: { minPx: 8, maxPx: 16 },
    }),
    overlap("status-badge", "avatar", {
      horizontal: { minPx: 8 },
      vertical: { minPx: 8 },
    }),
    inside("status-badge", "avatar", {
      tolerancePx: 4,
    }),
  ],
});

assertLayout(report);
```

`checkLayout` returns all independent invalid-rule, element-resolution,
visibility, and geometry findings in one JSON-serializable report. Use
`assertLayout` when a failing report should throw `LayoutAssertionError`; the
error retains the original report by identity.

## Geometry contract

- Relationship helpers use `subject, reference` argument order.
- Measurements use viewport-relative `Element.getBoundingClientRect()` border
  rectangles in fractional CSS pixels.
- Test IDs are exact and case-sensitive. Whitespace is preserved.
- Every check measures all referenced elements in one browser-side snapshot.
- Missing, duplicate, hidden, and zero-size elements are report findings rather
  than arbitrary element selection or implicit waiting.
- The package root has no Playwright runtime dependency or browser side effects.

V1 verifies alignment, directional ordering and gaps, overlap depth,
non-overlap, containment, width, height, and size. It does not judge typography,
color, hierarchy, aesthetics, occlusion, or irregular shapes.

## License

MIT
